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
        INSERT INTO MeetingRooms VALUES (floor, room, rname, did); -- floor and room primary key
        INSERT INTO Updates VALUES (date, room_capacity, floor, room, manager_id);
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
        INSERT INTO Updates VALUES (date, room_capacity, floor, room, manager_id);
    ELSE
        RAISE EXCEPTION 'Manager department % does not match room department %', man_did, room_did;
    END IF;

    -- Cancel all future meetings beyond date where participants > capacity regardless of approval status

    WITH ExceedCap AS
        (SELECT S.floor, S.room, S.date, S.time, COUNT(*)
        FROM Sessions S JOIN Joins J 
        ON S.date = J.date AND S.time = J.time AND S.floor = J.floor AND S.room = J.room 
        WHERE S.date > date -- Change this if want to include same day meetings
        GROUP BY (S.floor, S.room, S.date, S.time)
        HAVING COUNT(*) > room_capacity)

    DELETE FROM Sessions S 
    WHERE S.floor IN (SELECT E.floor FROM ExceedCap E)
        AND S.room IN (SELECT E.room FROM ExceedCap E) 
        AND S.date IN (SELECT E.date FROM ExceedCap E);
        --AND S.time IN (SELECT E.time FROM ExceedCap E)
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

    IF designation NOT IN ('Junior', 'Senior', 'Manager') THEN
        RAISE EXCEPTION 'Wrong role given -> %.', designation;
    END IF; 
    
    INSERT INTO Employees VALUES (new_eid, did, ename, email, home_phone, mobile_phone, office_phone, resigned_date);

    IF designation = 'Junior' THEN 
        INSERT INTO Junior VALUES(new_eid);
    ELSIF designation = 'Senior' THEN 
        INSERT INTO Booker VALUES (new_eid);
        INSERT INTO Senior VALUES(new_eid); 
    ELSIF designation = 'Manager' THEN 
        INSERT INTO Booker VALUES (new_eid);
        INSERT INTO Manager VALUES (new_eid); 
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
    END IF;

    UPDATE Employees E
    SET resigned_date = date
    WHERE E.eid = emp_id;

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
            (SELECT *, ROW_NUMBER() OVER (PARTITION BY U.floor, U.room ORDER BY date DESC) AS row_num
            FROM Updates U
            WHERE U.date <= session_date::date)
        SELECT M.floor, M.room, F.new_capacity as capacity, M.did
        FROM FilteredAndSortedUpdates F, MeetingRooms M
        WHERE row_num = 1 AND F.room = M.room AND F.floor = M.floor)
    SELECT R.floor, R.room, R.did, R.capacity
    FROM RoomWithCapacity R
    WHERE R.capacity >= search_capacity AND (R.floor, R.room) NOT IN (SELECT DISTINCT floor, room
                                                                      FROM Sessions S
                                                                      WHERE session_date = S.date AND 
                                                                            S.time BETWEEN start_hour AND end_hour-1)
    ORDER BY R.capacity;
END;
$$ LANGUAGE plpgsql;

-- Book Room
-- 1. Only a senior employee or manager can book a room. (enforced by FK Sessions.booker_id -> Booker.eid)
-- 2. If the room is not available for the given session, no booking can be done.
-- 3. If the employee is having a fever or has not declared health declaration, they cannot book any room.
CREATE OR REPLACE PROCEDURE book_room(floor_number INT, room_number INT, session_date DATE, start_hour INT, end_hour INT, booker_id INT, booking_date DATE)
AS $$
BEGIN
    IF NOT EXISTS (SELECT * FROM HealthDeclaration H WHERE H.eid = booker_id AND H.date = booking_date AND H.temperature <= 37.5) THEN
        RAISE EXCEPTION 'Employee % has not declared daily health declaration or is having a fever', booker_id;

    ELSIF EXISTS (SELECT * FROM Sessions S WHERE S.floor = floor_number AND S.room = room_number AND S.date = session_date AND S.time BETWEEN start_hour and end_hour-1) THEN
        RAISE EXCEPTION 'Meeting Room (Floor % Room %) is not available for booking', floor_number, room_number;
    END IF;
    
    for counter in start_hour..(end_hour-1) LOOP
        INSERT INTO Sessions VALUES (session_date, counter, room_number, floor_number, booker_id, NULL);
    END LOOP;
END
$$ LANGUAGE plpgsql;

-- Book room triggers
-- 1. The employee booking the room immediately joins the booked meeting.
DROP TRIGGER IF EXISTS booker_joins_meeting ON Sessions;
CREATE TRIGGER booker_joins_meeting AFTER INSERT ON Sessions
FOR EACH ROW EXECUTE FUNCTION booker_joins_meeting();

CREATE OR REPLACE FUNCTION booker_joins_meeting()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO Joins VALUES (NEW.booker_id, NEW.date, NEW.time, NEW.floor, NEW.room);
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- 2. If employee is resigned, they cannot book any meetings.
DROP TRIGGER IF EXISTS check_booker_not_resigned ON Sessions;
CREATE TRIGGER check_booker_not_resigned BEFORE INSERT ON Sessions
FOR EACH ROW EXECUTE FUNCTION check_booker_not_resigned();

CREATE OR REPLACE FUNCTION check_booker_not_resigned()
RETURNS TRIGGER AS $$
DECLARE resigned_date DATE;
BEGIN
    SELECT E.resigned_date INTO resigned_date
    FROM Employees E
    WHERE E.eid = NEW.booker_id;

    IF resigned_date IS NOT NULL THEN
        RAISE NOTICE 'Employee % has already resigned, cannot book meeting', NEW.booker_id;
        RETURN NULL;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Unbook Room
-- 1. If this is not the employee doing the booking, the employee is not allowed to remove booking
CREATE OR REPLACE PROCEDURE unbook_room(floor_number INT, room_number INT, session_date DATE, start_hour INT, end_hour INT, unbooker_id INT)
AS $$
DECLARE booker_id INTEGER;
BEGIN
    for counter in start_hour..(end_hour-1) LOOP
        SELECT S.booker_id INTO booker_id
        FROM Sessions S
        WHERE S.date = session_date AND S.floor = floor_number
              AND S.room = room_number AND S.time = counter;
        
        IF unbooker_id <> booker_id THEN
            RAISE NOTICE 'Unable to remove booking, employee_id % does not match booker_id %', unbooker_id, booker_id;
        ELSE
            DELETE FROM Sessions S
            WHERE S.date = session_date AND S.floor = floor_number
                  AND S.room = room_number AND S.time = counter;
        END IF;
    END LOOP;
END
$$ LANGUAGE plpgsql;


-- Add Health Declaration for an Employee
CREATE OR REPLACE PROCEDURE declare_health (emp_id INTEGER, date DATE, temperature NUMERIC)
AS $$

DECLARE have_fever BOOLEAN := false; 

BEGIN
	IF temperature > 37.5 THEN have_fever := true;
	END IF;
    INSERT INTO HealthDeclaration VALUES (emp_id, date, temperature, have_fever);
END
$$ LANGUAGE plpgsql;

-- Contact Tracing for an Employee
CREATE OR REPLACE FUNCTION contact_tracing (IN emp_id INTEGER, IN curr_date DATE)
RETURNS TABLE(close_contacts_eid INTEGER)
AS $$

DECLARE have_fever BOOLEAN := false; 

BEGIN
	SELECT EXISTS (SELECT 1 FROM HealthDeclaration h 
				   WHERE h.eid = emp_id AND h.fever = 'true' AND h.date = curr_date) INTO have_fever;

    IF have_fever = false THEN 
        RAISE EXCEPTION 'Employee % does not have fever or did not make a health declaration on this date %.', emp_id, curr_date; 
    ELSE 
		-- Creating temporary table to hold close contact employee id values
		DROP TABLE IF EXISTS close_contacts_list;
		CREATE TEMPORARY TABLE close_contacts_list(
			eid INTEGER
		);
		
		INSERT INTO close_contacts_list SELECT DISTINCT j2.eid AS eid
 			FROM Joins j, Joins j2, Sessions s
			WHERE j.date = s.date AND j.time = s.time
			AND j.room = s.room AND j.floor = s.floor
			AND j2.date = s.date AND j2.time = s.time
			AND j2.room = s.room AND j2.floor = s.floor
			AND j.eid <> j2.eid AND s.approver_id IS NOT NULL 
			AND emp_id = j.eid AND s.date BETWEEN curr_date - 3 AND curr_date;
			
		-- Remove bookings where the booker has a fever, approved or not.
		DELETE FROM Sessions s WHERE s.booker_id = emp_id AND curr_date <= s.date;
		
		-- Remove employee having fever from all future meetings.
		DELETE FROM JOINS j WHERE emp_id = j.eid AND curr_date <= j.date;
		
		-- Remove close contact employees for future meetings in the next 7 days.
		DELETE FROM Joins j
		WHERE j.eid IN (SELECT eid FROM close_contacts_list)
		AND j.date BETWEEN curr_date AND curr_date + 7;
		
		-- Remove bookings where the close contact employee is a booker, approved or not.
		DELETE FROM Sessions s 
		WHERE s.booker_id IN (SELECT eid FROM close_contacts_list) 
		AND s.date BETWEEN curr_date AND curr_date + 7;

		RETURN QUERY SELECT * FROM close_contacts_list;
		
	END IF;
END
$$ LANGUAGE plpgsql;

------------------------------- trigger function for join meeting --------------------------------
CREATE OR REPLACE FUNCTION check_join_meeting()
RETURNS TRIGGER AS $$
DECLARE 
    is_fever BOOLEAN;
    meeting_date DATE;
    meeting_time INT;
    meeting_room INT;
    meeting_floor INT;
    meeting_approver_id INT;
    meeting_capacity INT := 0;
    current_capacity INT := 0;

BEGIN
    SELECT HD.fever INTO is_fever
    FROM HealthDeclaration HD
    WHERE NEW.eid = HD.eid
    AND HD.date = CURRENT_DATE
    ;

    IF is_fever = TRUE THEN
        RAISE NOTICE 'Employee % has fever, unable to join meeting', NEW.eid;
        RETURN NULL;
    ELSIF is_fever IS NULL THEN
        RAISE NOTICE 'Employee % has not done health declaration, unable to join meeting', NEW.eid;
        RETURN NULL;
    END IF;

    SELECT S.date, S.time, S.room, S.floor, S.approver_id INTO meeting_date, meeting_time, 
    meeting_room, meeting_floor, meeting_approver_id
    FROM Sessions S
    WHERE S.date = NEW.date AND S.time = NEW.time 
    AND S.room = NEW.room AND S.floor = NEW.floor
    ;

    IF meeting_date IS NULL OR meeting_time IS NULL THEN
        RAISE NOTICE 'meeting on % % at floor % room % does not exist', NEW.date, NEW.time, NEW.floor, NEW.room;
        RETURN NULL;
    
    END IF;

    -- RAISE NOTICE 'current date = %, current time = %',
    --     CURRENT_DATE, CURRENT_TIME;
    IF meeting_date < CURRENT_DATE THEN
        RAISE NOTICE 'meeting at % % has passed, unable to join',
            meeting_date, meeting_time;
        RETURN NULL;
    ELSE
        IF meeting_date = CURRENT_DATE AND (TIME '00:00:00' + meeting_time * INTERVAL '1 hour') < CURRENT_TIME THEN
            RAISE NOTICE 'meeting has at % % has passed, unable to join',
            meeting_time, meeting_date;
            RETURN NULL;
        END IF;
    END IF;

    IF meeting_approver_id IS NOT NULL THEN
        RAISE NOTICE 'meeting on % % at floor % room % approved, unable to join', NEW.date, NEW.time, NEW.floor, NEW.room;
        RETURN NULL;
    END IF;

    -- get the latest capacity of the meeting room
    WITH DatesBeforeMeeting AS (
        SELECT date AS prev_date
        FROM Updates
        WHERE date <= meeting_date
        AND room = meeting_room
        AND floor = meeting_floor
    )
    SELECT U.new_capacity INTO meeting_capacity
    FROM Updates U
    WHERE U.room = meeting_room
    AND U.floor = meeting_floor
    AND U.date = (
        SELECT MAX(prev_date)
        FROM DatesBeforeMeeting
    )
    ;

    SELECT COUNT(eid) INTO current_capacity
    FROM Joins 
    WHERE date = meeting_date AND time = meeting_time
    AND room = meeting_room AND floor = meeting_floor
    GROUP BY (date, time, floor, room);

    RAISE NOTICE 'current capacity = %, max capacity = %',
        current_capacity, meeting_capacity;

    IF current_capacity + 1 > meeting_capacity THEN
        RAISE NOTICE 'meeting on % % at floor % room % is full, unable to join', NEW.date, NEW.time, NEW.floor, NEW.room;
        RETURN NULL;
    ELSE
        RAISE NOTICE 'Employee % joined meeting on % % at floor % room %', NEW.eid, NEW.date, NEW.time, NEW.floor, NEW.room;
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

------------------------------- trigger function for approve meeting -----------------------------
CREATE OR REPLACE FUNCTION check_approve_meeting()
RETURNS TRIGGER AS $$
DECLARE
    employee_resigned_date DATE;
    meeting_approver_id INT;
    employee_did INT;
    -- meeting_room_did INT;
BEGIN
    SELECT S.approver_id INTO meeting_approver_id
    FROM Sessions S
    WHERE S.date = NEW.date AND S.time = NEW.time
    AND S.room = NEW.room AND S.floor = NEW.floor;

    IF meeting_approver_id IS NOT NULL THEN
        RAISE NOTICE 'meeting on % % at floor % room % already approved, unable to approve again', NEW.date, NEW.time, NEW.floor, NEW.room;
        RETURN NULL;
    END IF;

    SELECT resigned_date INTO employee_resigned_date
    FROM Employees
    WHERE eid = NEW.approver_id;

    IF employee_resigned_date IS NOT NULL AND employee_resigned_date < CURRENT_DATE THEN
        RAISE NOTICE 'employee % already resigned, cannot approve meeting', NEW.approver_id;
        RETURN NULL;
    END IF; 

    RAISE NOTICE 'Manager eid % approved booking for meeting room at floor % room %', 
    NEW.approver_id, NEW.floor, NEW.room;
    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

---------------------creating triggers ------------------------
DROP TRIGGER IF EXISTS employee_joining
ON Joins;

DROP TRIGGER IF EXISTS approving_meeting
ON Sessions;

CREATE TRIGGER employee_joining
BEFORE INSERT
ON Joins
FOR EACH ROW
EXECUTE FUNCTION check_join_meeting();

CREATE TRIGGER approving_meeting
BEFORE UPDATE
ON Sessions
FOR EACH ROW
EXECUTE FUNCTION check_approve_meeting();

----------------- join_meeting ----------------------------------------------
-- 1. Employee must have done health declaration and has no fever on current day
-- 2. Employee can only join future meeting
-- 3. Any employee can join a booked meeting
-- 4. Employee cannot join meeting that is already approved
-- 5. Employee can join meeting only if max capacity not reached
CREATE OR REPLACE FUNCTION join_meeting 
(eid INT, meeting_date DATE, start_hour INT, end_hour INT, floor INT, room INT)
RETURNS VOID AS $$
DECLARE 
    curr_hour INT := start_hour;
BEGIN
    LOOP
        EXIT WHEN curr_hour > end_hour;
        INSERT INTO Joins
        VALUES (eid, meeting_date, curr_hour, floor, room);
        curr_hour := curr_hour + 1;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------------------------------

----------------- leave meeting -----------------------------------------------
-- 1. Employee cannot leave meeting that is already approved
-- 2. Employee can only leave from a future meeting
CREATE OR REPLACE FUNCTION leave_meeting
(employee_id INT, meeting_date DATE, start_hour INT, end_hour INT, floor_num INT, room_num INT)
RETURNS VOID AS $$
DECLARE
    curr_hour INT:= start_hour;
    meeting_approver_id INT;
BEGIN

    IF meeting_date < CURRENT_DATE THEN
        RAISE NOTICE 'meeting on % already passed, unable to leave meeting', meeting_date;
        RETURN;
    ELSE
        IF meeting_date = CURRENT_DATE AND (TIME'00:00:00' + start_hour * INTERVAL '1hour') < CURRENT_TIME THEN
            RAISE NOTICE 'meeting on % already passed, unable to leave meeting', meeting_date;
            RETURN;
        END IF;
    END IF;

    LOOP
        EXIT WHEN curr_hour > end_hour;

        SELECT S.approver_id INTO meeting_approver_id
        FROM Joins J, Sessions S
        WHERE J.eid = employee_id
        AND J.date = S.date AND J.time = S.time 
        AND J.room = S.room AND J.floor = S.floor;

        --- can be meeting does not exist or remove that employee
        IF meeting_approver_id IS NULL THEN
            DELETE FROM Joins J
            WHERE J.eid = employee_id AND J.date = meeting_date
            AND J.time = curr_hour
            AND J.room = room_num AND J.floor = floor_num;
            RAISE NOTICE 'meeting does not exist or employee % removed', employee_id;
        ELSE
            RAISE NOTICE 'meeting on % % at floor % room % already approved', meeting_date, curr_hour, floor_num, room_num;
        END IF;
        curr_hour := curr_hour + 1;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------------------------------

---------------------------------- approve_meeting ----------------------------
-- 1. Only manager from the same department can approve a meeting
-- 2. If meeting is not approved (rejected), remove the meeting session
-- 3. Manager can only approve future meetings
-- 4. If manager resigned, cannot approve
-- 5. If meeting already approved, cannot approve again
CREATE OR REPLACE FUNCTION approve_meeting 
(employee_id INT, meeting_date DATE, start_hour INT, end_hour INT, floor_num INT, room_num INT, status CHAR(1))
RETURNS VOID AS $$
DECLARE 
    curr_hour INT := start_hour;
    meeting_approver_id INT;
    employee_did INT;
    meeting_room_did INT;

BEGIN
    SELECT M.eid INTO meeting_approver_id
    FROM Manager M
    WHERE M.eid = employee_id;

    IF meeting_approver_id IS NULL THEN
        RAISE NOTICE 'Employee % not a manager, unable to approve meeting',
            employee_id;
        RETURN;
    END IF;

    SELECT M.did INTO meeting_room_did
    FROM MeetingRooms M
    WHERE M.room = room_num
    AND M.floor = floor_num;

    SELECT E.did INTO employee_did
    FROM Employees E
    WHERE E.eid = employee_id;

    IF meeting_room_did <> employee_did THEN
        RAISE NOTICE 'approver and meeting room do not belong to same department, cannot approve meeting';
        RETURN;
    END IF;

    IF meeting_date < CURRENT_DATE THEN
        RAISE NOTICE 'meeting already passed, unable to approve meeting';
        RETURN;
    ELSE 
        IF meeting_date = CURRENT_DATE AND (TIME'00:00:00' + start_hour * INTERVAL '1 hour') < CURRENT_TIME THEN
            RAISE NOTICE 'meeting already passed, unable to leave meeting';
            RETURN;
        ELSE
            LOOP
                EXIT WHEN curr_hour > end_hour;
                IF lower(status) = 'f' THEN
                    DELETE FROM Sessions
                    WHERE date = meeting_date AND time = curr_hour
                    AND room = room_num AND floor = floor_num;
                    RAISE NOTICE 'Manager eid % from dept % rejected booking for meeting room from dpt 
                    on % at floor % room %', employee_id, employee_did, meeting_room_did, floor_num, room_num;
                    RAISE NOTICE 'Session removed';
                ELSE
                    UPDATE Sessions
                    SET date = meeting_date,
                    time = curr_hour,
                    room = room_num, floor = floor_num, approver_id = employee_id
                    WHERE date = meeting_date AND time = curr_hour
                    AND room = room_num and floor = floor_num;
                END IF;
                curr_hour := curr_hour + 1;
            END LOOP;            
        END IF;
    END IF;
END;
$$ LANGUAGE plpgsql;
-------------------------------------------------------------------------------


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