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
END
$$ LANGUAGE plpgsql;

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
