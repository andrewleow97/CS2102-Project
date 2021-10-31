-- PROC SQL PL/pgSQL routines of implementation need to run with psql

-- Basic Functions

-- Add Department
CREATE OR REPLACE PROCEDURE add_department (did INTEGER, dname TEXT)
AS $$
BEGIN
    INSERT INTO Departments VALUES (did, dname);
END
$$ LANGUAGE plpgsql;

-- Remove Department (assume employees no longer belong to this department)
CREATE OR REPLACE PROCEDURE remove_department (did INTEGER)
AS $$
BEGIN
    DELETE FROM Departments D WHERE D.did = did;
END
$$ LANGUAGE plpgsql;

-- Add Meeting Room
CREATE OR REPLACE PROCEDURE add_room (floor INTEGER, room INTEGER, rname TEXT, did INTEGER, room_capacity INTEGER, manager_id INTEGER)
AS $$
DECLARE date DATE := CURRENT_DATE;
DECLARE man_did INTEGER := 0;
BEGIN
    SELECT E.did INTO man_did FROM Employees E WHERE E.eid = manager_id;
    IF man_did = did THEN 
        INSERT INTO MeetingRooms VALUES (room, floor, rname, did); -- floor and room primary key
        INSERT INTO Updates VALUES (date, room_capacity, room, floor, manager_id);
    ELSE 
        RAISE EXCEPTION 'Manager department % does not match room department %', man_did, did;
    END IF;
END
$$ LANGUAGE plpgsql;

-- Change Meeting Room Capacity
CREATE OR REPLACE PROCEDURE change_capacity (floor INTEGER, room INTEGER, room_capacity INTEGER, date DATE, manager_id INTEGER)
AS $$
DECLARE man_did INTEGER := 0;
DECLARE room_did INTEGER := 0;
BEGIN
    SELECT E.did INTO man_did FROM Employees E WHERE E.eid = manager_id;
    SELECT M.did INTO room_did FROM MeetingRooms M WHERE M.floor = floor AND M.room = room;

    IF man_did = room_did THEN
        INSERT INTO Updates VALUES (date, room_capacity, room, floor, manager_id);
    ELSE
        RAISE EXCEPTION 'Manager department % does not match room department %', man_did, room_did;
    END IF;

    -- Cancel all future meetings beyond date where participants > capacity regardless of approval status

    WITH ExceedCap AS (SELECT S.room, S.floor, S.date, S.time, COUNT(*)
    FROM Sessions S JOIN Joins J 
    ON S.date = J.date AND S.time = J.time AND S.room = J.room AND S.floor = J.floor
    WHERE S.date > date -- Change this if want to include same day meetings
    GROUP BY (S.room, S.floor, S.date, S.time)
    HAVING COUNT(*) > room_capacity)

    DELETE FROM Sessions S 
    WHERE S.room IN (SELECT E.room FROM ExceedCap E) 
    AND S.floor IN (SELECT E.floor FROM ExceedCap E)
    AND S.date IN (SELECT E.date FROM ExceedCap E);
END
$$ LANGUAGE plpgsql;

-- Add Employee
CREATE OR REPLACE PROCEDURE add_employee (did INTEGER, ename TEXT, home_phone INTEGER, mobile_phone INTEGER, office_phone INTEGER, designation TEXT)
AS $$
DECLARE new_eid INTEGER := 0;
DECLARE email TEXT := NULL;
DECLARE resigned_date DATE := NULL;
BEGIN
    SELECT eid INTO new_eid FROM Employees ORDER BY eid DESC LIMIT 1;
    new_eid := new_eid + 1;
    email := CONCAT(ename, new_eid::TEXT, '@gmail.com');

    IF designation IN ('Junior', 'Senior', 'Manager') THEN
        INSERT INTO Employees VALUES (new_eid, did, ename, email, home_phone, mobile_phone, office_phone, resigned_date);
    ELSE 
        RAISE EXCEPTION 'Wrong role given -> %.', designation;
    END IF;

    IF designation = 'Junior' THEN 
        INSERT INTO Junior VALUES(new_eid);
    ELSIF designation = 'Senior' THEN 
        INSERT INTO Senior VALUES(new_eid); 
        INSERT INTO Booker VALUES (new_eid);
    ELSIF designation = 'Manager' THEN 
        INSERT INTO Manager VALUES (new_eid); INSERT INTO Booker VALUES (new_eid);

    END IF;
END
$$ LANGUAGE plpgsql;

-- Remove Employee (only set resigned date, don't remove record)
CREATE OR REPLACE PROCEDURE remove_employee (emp_id INTEGER, date DATE)
AS $$
DECLARE eid_exist BOOLEAN := true;
BEGIN
    SELECT EXISTS (SELECT eid FROM Employees E WHERE E.eid = emp_id) INTO eid_exist;

    IF eid_exist = false THEN 
        RAISE EXCEPTION 'Employee % does not exist', emp_id; 
    ELSE 
        UPDATE Employees E
        SET resigned_date = date
        WHERE E.eid = emp_id;
    END IF;

    -- Remove this employee from all sessions beyong their resignation date, regardless of session approval status
    DELETE FROM Joins J WHERE J.eid = eid AND J.date > date::DATE;
END
$$ LANGUAGE plpgsql;


-- Core Functions

-- Search Room
CREATE OR REPLACE FUNCTION search_room(search_capacity INT, session_date DATE, start_hour INT, end_hour INT)
RETURNS TABLE(floor_number INT, room_number INT, department_id INT, room_capacity INT) AS $$
BEGIN
    RETURN QUERY WITH RoomWithCapacity AS
        (WITH FilteredAndSortedUpdates AS
            (SELECT *, ROW_NUMBER() OVER (PARTITION BY U.floor, U.room_number ORDER BY date DESC) AS row_num
            FROM Updates U
            WHERE U.date <= session_date::date)
        SELECT M.floor, M.room_number, F.new_capacity as capacity, M.did
        FROM FilteredAndSortedUpdates F, MeetingRooms M
        WHERE row_num = 1 AND F.room_number = M.room_number AND F.floor = M.floor)
    SELECT R.floor, R.room_number, R.did, R.capacity
    FROM RoomWithCapacity R
    WHERE R.capacity >= search_capacity AND (R.floor, R.room_number) NOT IN (SELECT DISTINCT floor, room
                                                                             FROM Sessions S
                                                                             WHERE session_date = S.date AND 
                                                                                   S.time BETWEEN start_hour AND end_hour-1)
    ORDER BY R.capacity;
END;
$$ LANGUAGE plpgsql;


-- Book Room
-- 1. Only a senior employee or manager can book a room.
-- 2. If the room is not available for the given session, no booking can be done.
-- 3. If the employee is having a fever, they cannot book any room.
-- 4. If the employee has not declared health declaration on the date of booking, they cannot book any room.
CREATE OR REPLACE PROCEDURE book_room(floor_number INT, room_number INT, session_date DATE, start_hour INT, end_hour INT, booker_id INT)
AS $$
DECLARE booking_date DATE := CURRENT_DATE;
BEGIN
    IF NOT EXISTS (SELECT * FROM Manager M WHERE booker_id = M.eid) AND NOT EXISTS (SELECT 1 FROM Senior S WHERE booker_id = S.eid) THEN
        RAISE EXCEPTION 'Employee % is not a senior or manager', booker_id;
    
    ELSIF NOT EXISTS (SELECT * FROM HealthDeclaration H WHERE H.eid = booker_id AND H.date = booking_date AND H.temperature <= 37.5) THEN
        RAISE EXCEPTION 'Employee % has not declared daily health declaration or is having a fever', booker_id;
    
    ELSIF EXISTS (SELECT * FROM Sessions S WHERE S.floor = floor_number AND S.room = room_number AND S.date = session_date AND S.time BETWEEN start_hour and end_hour-1) THEN
        RAISE EXCEPTION 'Meeting Room (Floor % Room %) is not available for booking', floor_number, room_number;
    
    ELSE 
        for counter in start_hour..(end_hour-1) LOOP
            INSERT INTO Sessions VALUES (session_date, counter, room_number, floor_number, booker_id, NULL);
            INSERT INTO Joins VALUES (booker_id, session_date, counter, room_number, floor_number);
        END LOOP;

    END IF;
END
$$ LANGUAGE plpgsql;


-- Unbook Room
-- 1. If this is not the employee doing the booking, the employee is not allowed to remove booking
CREATE OR REPLACE PROCEDURE unbook_room(floor_number INT, room_number INT, session_date DATE, start_hour INT, end_hour INT, unbooker_id INT)
AS $$
DECLARE booker_id INTEGER := 0;
BEGIN
    for counter in start_hour..(end_hour-1) LOOP
        SELECT S.booker_id INTO booker_id
        FROM Sessions S
        WHERE S.date = session_date AND S.floor = floor_number
              AND S.room = room_number AND S.time = counter;
        
        -- If unbooker_id <> booker_id, continue searching for bookings with same id for removal.
        IF unbooker_id = booker_id THEN
            DELETE FROM Sessions S
            WHERE S.date = session_date AND S.floor = floor_number
                  AND S.room = room_number AND S.time = counter;
        END IF;
    END LOOP;
END
$$ LANGUAGE plpgsql;


-- Admin Functions

-- Non-Compliance

CREATE OR REPLACE FUNCTION non_compliance(IN start_date DATE, IN end_date DATE)
RETURNS TABLE(EmployeeId INTEGER, Number_of_Days INTEGER) AS $$
DECLARE curr_date DATE := start_date;
BEGIN
    -- Creating temporary table to hold employee id values
    DROP TABLE IF EXISTS non_compliant_list;
    CREATE TEMPORARY TABLE non_compliant_list(
        eid INTEGER
    );

    -- Date checking if valid
    IF end_date < start_date THEN 
        RAISE EXCEPTION 'End date % is before start date %', end_date, start_date;
    END IF;

    WHILE curr_date <= end_date LOOP -- dates inclusive
        -- List of employees on this date that do not have a health declaration
        WITH emp_list AS (SELECT DISTINCT E.eid FROM Employees E WHERE E.eid NOT IN (SELECT DISTINCT H.eid FROM HealthDeclaration H WHERE H.date = curr_date))
        -- Insert into temporary table for counting days later
        INSERT INTO non_compliant_list SELECT * FROM emp_list;

        -- Advance loop
        curr_date := curr_date + 1; 
    END LOOP;
    
    -- Selects employee ID and number of days they have not declared temperature
    RETURN QUERY SELECT eid AS EmployeeId, COUNT(*)::INTEGER AS Number_of_Days
    FROM non_compliant_list
    GROUP BY eid
    ORDER BY Number_of_Days DESC, eid ASC;
END;
$$ LANGUAGE plpgsql;


-- View Booking Report
CREATE OR REPLACE FUNCTION view_booking_report(IN start_date DATE, IN eid INTEGER)
RETURNS TABLE(floor INTEGER, room INTEGER, date DATE, start_hour INTEGER, approved BOOLEAN) AS $$
BEGIN
    RETURN QUERY SELECT S.floor, S.room, S.date, S.time, S.approver_id IS NOT NULL
    FROM Sessions S
    WHERE S.date >= start_date AND eid = S.booker_id
    ORDER BY S.date ASC, S.time ASC;
END;
$$ LANGUAGE plpgsql;


-- View Future Meetings
CREATE OR REPLACE FUNCTION view_future_meeting(IN start_date DATE, IN emp_id INTEGER)
RETURNS TABLE(floor INTEGER, room INTEGER, date DATE, start_hour INTEGER) AS $$
BEGIN
    RETURN QUERY SELECT S.floor, S.room, S.date, S.time 
    -- Check meetings where employee is attending
	FROM Sessions S JOIN Joins J 
    ON S.date = J.date 
       AND S.time = J.time
       AND S.room = J.room 
       AND S.floor = J.floor 
       AND J.eid = emp_id
    -- Check approved meeting and later start date
    WHERE S.approver_id IS NOT NULL AND S.date >= start_date 
    ORDER BY S.date ASC, S.time ASC;
END;
$$ LANGUAGE plpgsql;


-- View Manager Report
-- 1. If the employee ID does not belong to a manager, the routine returns an empty table.
-- 2. Returns a table containing all meeting that are booked but not yet approved from the given start date onwards.
-- 3. Return all meeting in the room with the same department as the manager
-- 4. The table should be sorted in ascending order of date and start hour.
CREATE OR REPLACE FUNCTION view_manager_report(start_date DATE, emp_id INTEGER)
RETURNS TABLE(floor INTEGER, room INTEGER, date DATE, start_hour INTEGER, employee_id INTEGER) AS $$
BEGIN
    IF NOT EXISTS (SELECT * FROM Manager WHERE eid = emp_id) THEN
        RETURN;
    END IF;

    RETURN QUERY SELECT S.floor, S.room, S.date, S.time, S.booker_id
    FROM Sessions S JOIN Employees E
    ON S.booker_id = E.eid
    WHERE E.did = (SELECT did FROM Employees WHERE eid = emp_id)
          AND S.approver_id IS NULL
          AND S.date > start_date -- given start date onwards, inclusive?
    ORDER BY S.date, S.time;
END;
$$ LANGUAGE plpgsql;