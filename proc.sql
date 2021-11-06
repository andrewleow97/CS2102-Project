-- PROC SQL PL/pgSQL routines of implementation need to run with psql

DROP FUNCTION IF EXISTS check_update_date() CASCADE;
DROP FUNCTION IF EXISTS senior_not_manager() CASCADE;
DROP FUNCTION IF EXISTS prevent_eid_email_name_update() CASCADE;
DROP FUNCTION IF EXISTS resign_remove() CASCADE;
DROP FUNCTION IF EXISTS find_room_capacity(date) CASCADE;
DROP FUNCTION IF EXISTS check_email_format() CASCADE;
DROP FUNCTION IF EXISTS check_name_format() CASCADE;
DROP FUNCTION IF EXISTS default_junior() CASCADE;
DROP FUNCTION IF EXISTS manager_not_senior() CASCADE;
DROP PROCEDURE IF EXISTS remove_employee(integer,date) CASCADE;
DROP FUNCTION IF EXISTS resigned_past_date() CASCADE;
DROP FUNCTION IF EXISTS junior_not_booker() CASCADE;
DROP FUNCTION IF EXISTS booker_not_junior() CASCADE;
DROP PROCEDURE IF EXISTS declare_health(integer,date,numeric) CASCADE;
DROP FUNCTION IF EXISTS check_for_fever() CASCADE;
DROP FUNCTION IF EXISTS view_manager_report(date,integer) CASCADE;
DROP PROCEDURE IF EXISTS book_room(integer,integer,date,integer,integer,integer) CASCADE;
DROP FUNCTION IF EXISTS booker_joins_meeting() CASCADE;
DROP PROCEDURE IF EXISTS unbook_room(integer,integer,date,integer,integer,integer) CASCADE;
DROP FUNCTION IF EXISTS check_delete_meeting() CASCADE;
DROP PROCEDURE IF EXISTS add_department(integer,text) CASCADE;
DROP FUNCTION IF EXISTS leave_meeting(integer,date,integer,integer,integer,integer) CASCADE;
DROP FUNCTION IF EXISTS view_booking_report(date,integer) CASCADE;
DROP FUNCTION IF EXISTS search_room(integer,date,integer,integer) CASCADE;
DROP FUNCTION IF EXISTS check_insert_booking() CASCADE;
DROP FUNCTION IF EXISTS check_join_meeting() CASCADE;
DROP PROCEDURE IF EXISTS add_room(integer,integer,text,integer,integer,integer) CASCADE;
DROP FUNCTION IF EXISTS check_employee_format() CASCADE;
DROP PROCEDURE IF EXISTS remove_department(integer) CASCADE;
DROP FUNCTION IF EXISTS remove_meetings() CASCADE;
DROP FUNCTION IF EXISTS contact_tracing(integer,date) CASCADE;
DROP FUNCTION IF EXISTS join_meeting(integer,date,integer,integer,integer,integer) CASCADE;
DROP FUNCTION IF EXISTS check_leave_meeting() CASCADE;
DROP FUNCTION IF EXISTS view_future_meeting(date,integer) CASCADE;
DROP FUNCTION IF EXISTS non_compliance(date,date) CASCADE;
DROP PROCEDURE IF EXISTS change_capacity(integer,integer,integer,date,integer) CASCADE;
DROP PROCEDURE IF EXISTS add_employee(integer,text,integer,integer,integer,text) CASCADE;
DROP FUNCTION IF EXISTS check_approve_meeting() CASCADE;
DROP FUNCTION IF EXISTS approve_meeting(integer,date,integer,integer,integer,integer,character) CASCADE;
-- Basic Functions

-- Add Department
CREATE OR REPLACE PROCEDURE add_department (did INTEGER, dname TEXT)
AS $$
BEGIN
    INSERT INTO Departments VALUES (did, dname);
END
$$ LANGUAGE plpgsql;

-- Remove Department (assume employees no longer belong to this department)
CREATE OR REPLACE PROCEDURE remove_department (department_id INTEGER)
AS $$
BEGIN
    DELETE FROM Departments D WHERE D.did = department_id;
END
$$ LANGUAGE plpgsql;

-- Add Meeting Room
CREATE OR REPLACE PROCEDURE add_room (floor INTEGER, room INTEGER, rname TEXT, did INTEGER, room_capacity INTEGER, manager_id INTEGER)
AS $$
DECLARE man_did INTEGER;
BEGIN
    SELECT E.did INTO man_did FROM Employees E WHERE E.eid = manager_id;

    IF man_did <> did THEN 
        RAISE EXCEPTION 'Manager department % does not match room department %', man_did, did;
    END IF;
    
    INSERT INTO MeetingRooms VALUES (floor, room, rname, did); -- floor and room primary key
    INSERT INTO Updates VALUES (CURRENT_DATE, room_capacity, floor, room, manager_id);
END
$$ LANGUAGE plpgsql;


-- Change Meeting Room Capacity
CREATE OR REPLACE PROCEDURE change_capacity (floor_num INTEGER, room_num INTEGER, room_capacity INTEGER, new_date DATE, manager_id INTEGER)
AS $$
DECLARE man_did INTEGER;
DECLARE room_did INTEGER;
BEGIN
    SELECT E.did INTO man_did FROM Employees E WHERE E.eid = manager_id;
    SELECT M.did INTO room_did FROM MeetingRooms M WHERE M.floor = floor_num AND M.room = room_num;

    IF man_did <> room_did THEN
      RAISE EXCEPTION 'Manager department % does not match room department %', man_did, room_did;
    END IF;

    IF new_date IN (SELECT DISTINCT date FROM Updates U WHERE floor_num = U.floor AND room_num = U.room) THEN
    UPDATE Updates SET new_capacity = room_capacity, eid = manager_id WHERE floor = floor_num AND room = room_num AND date = new_date;
    ELSE INSERT INTO Updates VALUES (new_date, room_capacity, floor_num, room_num, manager_id);
    END IF;
      
END
$$ LANGUAGE plpgsql;

------- TRIGGER TO CHECK DATE OF UPDATE >= CURRENT_DATE ----------------
CREATE OR REPLACE FUNCTION check_update_date()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.date < CURRENT_DATE THEN 
        RAISE NOTICE 'Update date should be in present or future, input date is %', NEW.date;
        RETURN NULL;
    ELSE RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS check_update_date_after_today ON Updates;
CREATE TRIGGER check_update_date_after_today BEFORE INSERT ON Updates
FOR EACH ROW EXECUTE FUNCTION check_update_date();

-- Cancel all future meetings beyond date where participants > capacity regardless of approval status
CREATE OR REPLACE FUNCTION remove_meetings()
RETURNS TRIGGER AS $$
BEGIN
    -- Selects meetings from sessions joins j to get session with participant count > new capacity
    WITH ExceedCap AS
        (SELECT S.floor, S.room, S.date, S.time, COUNT(*)
        FROM Sessions S JOIN Joins J 
        ON S.date = J.date AND S.time = J.time AND S.floor = J.floor AND S.room = J.room 
        WHERE S.date > NEW.date -- Change this if want to include same day meetings
        GROUP BY (S.floor, S.room, S.date, S.time)
        HAVING COUNT(*) > NEW.new_capacity)

    DELETE FROM Sessions S 
    WHERE S.floor IN (SELECT E.floor FROM ExceedCap E)
        AND S.room IN (SELECT E.room FROM ExceedCap E) 
        AND S.date IN (SELECT E.date FROM ExceedCap E)
        AND S.time IN (SELECT E.time FROM ExceedCap E);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


DROP TRIGGER IF EXISTS remove_meetings_exceeding ON Updates;
CREATE TRIGGER remove_meetings_exceeding AFTER INSERT OR UPDATE ON Updates
FOR EACH ROW EXECUTE FUNCTION remove_meetings(); 

-- Add Employee
CREATE OR REPLACE PROCEDURE add_employee (did INTEGER, ename TEXT, home_phone INTEGER, mobile_phone INTEGER, office_phone INTEGER, designation TEXT)
AS $$
DECLARE new_eid INTEGER := 0;
DECLARE email TEXT := NULL;
DECLARE resigned_date DATE := NULL;
BEGIN
    
    --The unique employee ID and email address are automatically generated by the system.
    SELECT MAX(eid) into new_eid from Employees;
    new_eid := new_eid + 1;
    email := CONCAT(ename, new_eid::TEXT, '@gmail.com');

    -- Can't do in trigger, designation is not a column
    IF LOWER(designation) NOT IN ('junior', 'senior', 'manager') THEN
        RAISE EXCEPTION 'Wrong role given -> %.', designation;
    END IF; 
    
    INSERT INTO Employees VALUES (new_eid, did, ename, email, home_phone, mobile_phone, office_phone, resigned_date);

    IF LOWER(designation) = 'junior' THEN 
        IF new_eid NOT IN (SELECT eid FROM Junior) THEN
            INSERT INTO Junior VALUES(new_eid);
        END IF;
    ELSIF LOWER(designation) = 'senior' THEN 
        INSERT INTO Booker VALUES (new_eid);
        INSERT INTO Senior VALUES(new_eid); 
    ELSIF LOWER(designation) = 'manager' THEN 
        INSERT INTO Booker VALUES (new_eid);
        INSERT INTO Manager VALUES (new_eid); 
    END IF;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION check_employee_format() 
RETURNS TRIGGER AS $$
DECLARE new_eid INTEGER;
DECLARE new_email TEXT;
BEGIN
    ---- Check eid format
    SELECT MAX(eid) INTO new_eid FROM Employees;
    new_eid := new_eid + 1;
    
    IF new_eid IS NULL THEN
        RETURN NEW;
    ELSIF NEW.eid = new_eid THEN
        RETURN NEW;
    ELSE
        RAISE NOTICE 'New employee ID % does not match next eid %', NEW.eid, new_eid;
        RETURN NULL;
    END IF;

END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS check_employee_format_in_order ON Employees;
CREATE TRIGGER check_employee_format_in_order BEFORE INSERT ON Employees 
FOR EACH ROW EXECUTE FUNCTION check_employee_format();

CREATE OR REPLACE FUNCTION check_email_format() 
RETURNS TRIGGER AS $$
DECLARE new_email TEXT;
BEGIN
    ---- Check email format
    new_email := CONCAT(NEW.ename, NEW.eid::TEXT, '@gmail.com');
    IF NEW.email = new_email THEN RETURN NEW;
    ELSE RAISE NOTICE 'New employee email % does not match email format %', NEW.email, new_email;
    RETURN NULL;
    END IF;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS check_email_format_in_order ON Employees;
CREATE TRIGGER check_email_format_in_order BEFORE INSERT ON Employees 
FOR EACH ROW EXECUTE FUNCTION check_email_format();

CREATE OR REPLACE FUNCTION check_name_format() 
RETURNS TRIGGER AS $$
DECLARE name_length INTEGER;
BEGIN
    ---- Check name format
    SELECT LENGTH(NEW.ename) INTO name_length;
    IF name_length < 1 THEN RAISE NOTICE 'Employee name % is too short', NEW.ename;
    RETURN NULL;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS check_name_format_in_order ON Employees;
CREATE TRIGGER check_name_format_in_order BEFORE INSERT ON Employees 
FOR EACH ROW EXECUTE FUNCTION check_name_format();

CREATE OR REPLACE FUNCTION default_junior() 
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO Junior VALUES (NEW.eid);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS default_role_junior ON Employees;
CREATE TRIGGER default_role_junior AFTER INSERT ON Employees 
FOR EACH ROW EXECUTE FUNCTION default_junior();

---- Check new Junior employee is not a Booker
CREATE OR REPLACE FUNCTION junior_not_booker() 
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.eid NOT IN (SELECT eid FROM Booker) THEN RETURN NEW;
    ELSE RAISE NOTICE 'Employee % is already a Booker, and cannot be a Junior', NEW.eid;
    RETURN NULL;
    END IF;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS junior_not_in_booker ON Junior;
CREATE TRIGGER junior_not_in_booker BEFORE INSERT ON Junior 
FOR EACH ROW EXECUTE FUNCTION junior_not_booker();

----- Check new Booker employee is not a Junior
CREATE OR REPLACE FUNCTION booker_not_junior() 
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.eid IN (SELECT eid FROM Junior) THEN
        DELETE FROM Junior WHERE eid = NEW.eid;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS booker_not_in_junior ON Booker;
CREATE TRIGGER booker_not_in_junior BEFORE INSERT ON Booker 
FOR EACH ROW EXECUTE FUNCTION booker_not_junior();

---- Check new Senior employee is not a Manager
CREATE OR REPLACE FUNCTION senior_not_manager() 
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.eid NOT IN (SELECT eid FROM Manager) THEN RETURN NEW;
    ELSE RAISE NOTICE 'Employee % is already a Manager, and cannot be a Senior', NEW.eid;
    RETURN NULL;
    END IF;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS senior_not_in_manager ON Senior;
CREATE TRIGGER senior_not_in_manager BEFORE INSERT ON Senior 
FOR EACH ROW EXECUTE FUNCTION senior_not_manager();

---- Check new Manager employee is not a Senior
CREATE OR REPLACE FUNCTION manager_not_senior() 
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.eid NOT IN (SELECT eid FROM Senior) THEN RETURN NEW;
    ELSE RAISE NOTICE 'Employee % is already a Senior, and cannot be a Manager', NEW.eid;
    RETURN NULL;
    END IF;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS manager_not_in_senior ON Manager;
CREATE TRIGGER manager_not_in_senior BEFORE INSERT ON Manager 
FOR EACH ROW EXECUTE FUNCTION manager_not_senior();

-- Remove Employee (only set resigned date, don't remove record)
CREATE OR REPLACE PROCEDURE remove_employee (emp_id INTEGER, date DATE)
AS $$
BEGIN
    IF NOT EXISTS (SELECT * FROM Employees E WHERE E.eid = emp_id) THEN 
        RAISE EXCEPTION 'Employee % does not exist', emp_id; 
    END IF;

    -- Update employees resignation date, should be in the past/present enforced by triggers
    UPDATE Employees E
    SET resigned_date = date
    WHERE E.eid = emp_id;

END
$$ LANGUAGE plpgsql;

---- Check RESIGNED DATE MUST BE IN PRESENT/PAST -------
CREATE OR REPLACE FUNCTION resigned_past_date() 
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.resigned_date <= CURRENT_DATE OR NEW.resigned_date IS NULL THEN RETURN NEW;
    ELSE RAISE NOTICE 'Resignation date % must be in the past or present', NEW.resigned_date;
    RETURN NULL;
    END IF;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS resigned_in_past ON Employees;
CREATE TRIGGER resigned_in_past BEFORE INSERT OR UPDATE ON Employees 
FOR EACH ROW EXECUTE FUNCTION resigned_past_date();

---- Check UPDATE ON EMPLOYEES -------
CREATE OR REPLACE FUNCTION prevent_eid_email_name_update() 
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.eid <> NEW.eid OR OLD.ename <> NEW.ename OR OLD.email <> NEW.email THEN RAISE NOTICE 'Cannot update employee eid, name or email';
    RETURN OLD;
    ELSE RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS check_employees_update ON Employees;
CREATE TRIGGER check_employees_update BEFORE UPDATE ON Employees 
FOR EACH ROW EXECUTE FUNCTION prevent_eid_email_name_update();

----approval status --------
CREATE OR REPLACE FUNCTION resign_remove()
RETURNS TRIGGER AS $$
BEGIN
    ALTER TABLE Joins DISABLE TRIGGER employee_leaving;
    DELETE FROM Joins J WHERE J.eid = NEW.eid AND J.date > NEW.resigned_date::DATE AND J.date >= CURRENT_DATE;
    ALTER TABLE Joins ENABLE TRIGGER employee_leaving;
    DELETE FROM Sessions S WHERE S.booker_id = NEW.eid AND S.date > NEW.resigned_date::DATE AND S.date >= CURRENT_DATE;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS remove_future_records ON Employees;
CREATE TRIGGER remove_future_records AFTER UPDATE ON Employees 
FOR EACH ROW EXECUTE FUNCTION resign_remove();

-- Core Functions

-- Helper function to find room capacity of meeting room at specified date
CREATE OR REPLACE FUNCTION find_room_capacity(search_date DATE)
RETURNS TABLE(floor INT, room INT, did INT, capacity INT) AS $$
BEGIN
    RETURN QUERY WITH FilteredAndSortedUpdates AS
        (SELECT *, ROW_NUMBER() OVER (PARTITION BY U.floor, U.room ORDER BY date DESC) AS row_num
        FROM Updates U
        WHERE U.date <= search_date::date)
    SELECT M.floor, M.room, M.did, F.new_capacity
    FROM FilteredAndSortedUpdates F, MeetingRooms M
    WHERE row_num = 1 AND F.room = M.room AND F.floor = M.floor;
END
$$ LANGUAGE plpgsql;

-- Search Room
-- 1.The table should be sorted in ascending order of capacity.
CREATE OR REPLACE FUNCTION search_room(search_capacity INT, session_date DATE, start_hour INT, end_hour INT)
RETURNS TABLE(floor_number INT, room_number INT, department_id INT, room_capacity INT) AS $$
BEGIN
    RETURN QUERY WITH RoomsWithCapacity AS
        (SELECT * FROM find_room_capacity(session_date))
    SELECT R.floor, R.room, R.did, R.capacity
    FROM RoomsWithCapacity R
    WHERE R.capacity >= search_capacity
        AND (R.floor, R.room) NOT IN (SELECT DISTINCT floor, room
                                      FROM Sessions S
                                      WHERE session_date = S.date
                                        AND S.time BETWEEN start_hour AND end_hour-1)
    ORDER BY R.capacity;
END
$$ LANGUAGE plpgsql;

-- Book Room
CREATE OR REPLACE PROCEDURE book_room(floor_number INT, room_number INT, session_date DATE, start_hour INT, end_hour INT, booker_id INT)
AS $$
BEGIN
    FOR counter IN start_hour..(end_hour-1) LOOP
        INSERT INTO Sessions VALUES (session_date, counter, room_number, floor_number, booker_id, NULL);
    END LOOP;
END
$$ LANGUAGE plpgsql;

-- Book Room Triggers
-- 1. If employee is resigned, they cannot book any meetings.
-- 2. If the employee is having a fever or has not declared health declaration, they cannot book any room.
-- 3. Employee can only book meetings on future dates.
CREATE OR REPLACE FUNCTION check_insert_booking()
RETURNS TRIGGER AS $$
DECLARE resigned_date DATE;
BEGIN
    SELECT E.resigned_date INTO resigned_date FROM Employees E WHERE E.eid = NEW.booker_id;

    IF resigned_date IS NOT NULL THEN
        RAISE EXCEPTION 'Employee % has already resigned, cannot book meeting', NEW.booker_id;
    END IF;

    IF NOT EXISTS (SELECT * FROM HealthDeclaration H WHERE H.eid = NEW.booker_id AND H.date = CURRENT_DATE AND H.fever = FALSE) THEN
        RAISE EXCEPTION 'Employee % has not declared daily health declaration or is having a fever', NEW.booker_id;
    END IF;

    IF NEW.date < CURRENT_DATE THEN
        RAISE EXCEPTION 'Cannot book meetings on dates that have past';
    END IF;

    RETURN NEW;
END
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS check_insert_booking ON Sessions;
CREATE TRIGGER check_insert_booking BEFORE INSERT ON Sessions
FOR EACH ROW EXECUTE FUNCTION check_insert_booking();

-- 4. The employee booking the room immediately joins the booked meeting.
CREATE OR REPLACE FUNCTION booker_joins_meeting()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO Joins VALUES (NEW.booker_id, NEW.date, NEW.time, NEW.floor, NEW.room);
    RETURN NULL;
END
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS booker_joins_meeting ON Sessions;
CREATE TRIGGER booker_joins_meeting AFTER INSERT ON Sessions
FOR EACH ROW EXECUTE FUNCTION booker_joins_meeting();

-- Room
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

-- Unbook Room Triggers
-- 1. Employees can only unbook future meetings.
CREATE OR REPLACE FUNCTION check_delete_meeting()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.date < CURRENT_DATE THEN
        RAISE EXCEPTION 'Cannot unbook meeting that has past %', OLD.date;
    END IF;

    RETURN OLD;
END
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS check_delete_meeting ON Sessions;
CREATE TRIGGER check_delete_meeting BEFORE DELETE ON Sessions
FOR EACH ROW EXECUTE FUNCTION check_delete_meeting();

-- Add Health Declaration for an Employee
CREATE OR REPLACE PROCEDURE declare_health (emp_id INTEGER, date DATE, temperature NUMERIC)
AS $$
BEGIN
    INSERT INTO HealthDeclaration VALUES (emp_id, date, temperature, 'false');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION check_for_fever()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.date <> CURRENT_DATE THEN
        RAISE EXCEPTION 'Health declaration date % is not the current date %.', NEW.date, CURRENT_DATE; 
    END IF;

    IF NEW.temperature > 37.5 THEN 
        NEW.fever = 'true';
    ELSE NEW.fever = 'false';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS check_for_fever_health_declaration ON HealthDeclaration;
CREATE TRIGGER check_for_fever_health_declaration BEFORE INSERT OR UPDATE ON HealthDeclaration
FOR EACH ROW EXECUTE FUNCTION check_for_fever();

-- Contact Tracing for an Employee
CREATE OR REPLACE FUNCTION contact_tracing (emp_id INTEGER, curr_date DATE)
RETURNS TABLE(close_contacts_eid INTEGER)
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM HealthDeclaration H WHERE H.eid = emp_id AND H.fever = TRUE AND H.date = curr_date) THEN 
        RAISE EXCEPTION 'Employee % does not have fever or did not make a health declaration on this date %.', emp_id, curr_date; 
    END IF;

    -- Creating temporary table to hold close contact employee id values
    DROP TABLE IF EXISTS close_contacts_list;
    CREATE TEMPORARY TABLE close_contacts_list(
        eid INTEGER
    );
    
    INSERT INTO close_contacts_list SELECT DISTINCT J2.eid AS eid
        FROM Joins J, Joins J2, Sessions S
        WHERE J.date = S.date AND J.time = S.time
            AND J.room = S.room AND J.floor = S.floor
            AND J2.date = S.date AND J2.time = S.time
            AND J2.room = S.room AND J2.floor = S.floor
            AND J.eid <> J2.eid AND S.approver_id IS NOT NULL 
            AND emp_id = J.eid AND S.date BETWEEN curr_date - 3 AND curr_date;
        
    ALTER TABLE Joins DISABLE TRIGGER employee_leaving;
    
    -- Remove bookings where the employee is the booker, approved or not.
    DELETE FROM Sessions S WHERE S.booker_id = emp_id AND curr_date <= S.date;
    
    -- Remove the employee from all future meetings, approved or not.
    DELETE FROM JOINS J WHERE emp_id = J.eid AND curr_date <= J.date;
    
    -- Remove close contact employees for future meetings in the next 7 days, approved or not.
    DELETE FROM Joins J
    WHERE J.eid IN (SELECT eid FROM close_contacts_list)
        AND J.date BETWEEN curr_date AND curr_date + 7;
    
    -- Remove bookings where the close contact employee is a booker, approved or not.
    DELETE FROM Sessions S 
    WHERE S.booker_id IN (SELECT eid FROM close_contacts_list) 
        AND S.date BETWEEN curr_date AND curr_date + 7;

    ALTER TABLE Joins ENABLE TRIGGER employee_leaving;
    
    RETURN QUERY SELECT * FROM close_contacts_list;
END
$$ LANGUAGE plpgsql;

-- Join Meeting Trigger
-- 1. Employee must have done health declaration and has no fever on current day
-- 2. Employee can only join future meeting
-- 3. Any employee can join a booked meeting
-- 4. Employee cannot join meeting that is already approved
-- 5. Employee can join meeting only if max capacity not reached
-- 6. Resigned employee cannot join meeting
CREATE OR REPLACE FUNCTION check_join_meeting()
RETURNS TRIGGER AS $$
DECLARE 
    is_fever BOOLEAN;
    employee_resigned_date DATE;
    meeting_date DATE;
    meeting_time INT;
    meeting_room INT;
    meeting_floor INT;
    meeting_approver_id INT;
    meeting_capacity INT := 0;
    current_capacity INT := 0;

BEGIN
    SELECT HD.fever INTO is_fever FROM HealthDeclaration HD WHERE NEW.eid = HD.eid AND HD.date = CURRENT_DATE;

    IF is_fever = TRUE THEN
        RAISE NOTICE 'Employee % has fever, unable to join meeting', NEW.eid;
        RETURN NULL;
    ELSIF is_fever IS NULL THEN
        RAISE NOTICE 'Employee % has not done health declaration, unable to join meeting', NEW.eid;
        RETURN NULL;
    END IF;
    
    SELECT S.date, S.time, S.room, S.floor, S.approver_id
    INTO meeting_date, meeting_time, meeting_room, meeting_floor, meeting_approver_id
    FROM Sessions S
    WHERE S.date = NEW.date AND S.time = NEW.time 
        AND S.room = NEW.room AND S.floor = NEW.floor;

    IF meeting_date < CURRENT_DATE THEN
        RAISE NOTICE 'meeting at % % has passed, unable to join', meeting_date, meeting_time;
        RETURN NULL;
    ELSE
        IF meeting_date = CURRENT_DATE AND (TIME '00:00:00' + meeting_time * INTERVAL '1 hour') < CURRENT_TIME THEN
            RAISE NOTICE 'meeting has at % % has passed, unable to join', meeting_time, meeting_date;
            RETURN NULL;
        END IF;
    END IF;

    IF meeting_approver_id IS NOT NULL THEN
        RAISE NOTICE 'meeting on % % at floor % room % approved, unable to join', NEW.date, NEW.time, NEW.floor, NEW.room;
        RETURN NULL;
    END IF;

    SELECT E.resigned_date INTO employee_resigned_date
    FROM Employees E
    WHERE E.eid = NEW.eid;

    IF employee_resigned_date IS NOT NULL AND employee_resigned_date < meeting_date THEN
        RAISE NOTICE 'employee % already resigned, cannot join meeting', NEW.eid;
        RETURN NULL;
    END IF; 

    WITH RoomsWithCapacity AS
        (SELECT * FROM find_room_capacity(meeting_date))
    SELECT R.capacity INTO meeting_capacity
    FROM RoomsWithCapacity R
    WHERE R.floor = meeting_floor
        AND R.room = meeting_room;

    SELECT COUNT(eid) INTO current_capacity
    FROM Joins 
    WHERE date = meeting_date AND time = meeting_time
        AND room = meeting_room AND floor = meeting_floor
    GROUP BY (date, time, floor, room);

    IF current_capacity + 1 > meeting_capacity THEN
        RAISE NOTICE 'meeting on % % at floor % room % is full, unable to join', NEW.date, NEW.time, NEW.floor, NEW.room;
        RETURN NULL;
    END IF;
    
    --RAISE NOTICE 'Employee % joined meeting on % % at floor % room %', NEW.eid, NEW.date, NEW.time, NEW.floor, NEW.room;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS employee_joining ON Joins;
CREATE TRIGGER employee_joining BEFORE INSERT ON Joins
FOR EACH ROW EXECUTE FUNCTION check_join_meeting();

-- Join Meeting
CREATE OR REPLACE FUNCTION join_meeting (eid INT, meeting_date DATE, start_hour INT, end_hour INT, floor INT, room INT)
RETURNS VOID AS $$
DECLARE 
BEGIN
    IF start_hour >= end_hour THEN
        RETURN;
    END IF;

    for counter in start_hour..(end_hour-1) LOOP
        INSERT INTO Joins VALUES (eid, meeting_date, counter, floor, room);
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Leave Meeting Trigger
-- 1. Employee cannot leave meeting that is already approved (not applicable if they have fever, is close contact or has resigned)
-- 2. Employee can only leave from a future meeting
CREATE OR REPLACE FUNCTION check_leave_meeting()
RETURNS TRIGGER AS $$
DECLARE
    meeting_date DATE;
    meeting_time INT;
    meeting_room INT;
    meeting_floor INT;
    meeting_approver_id INT;
BEGIN
    SELECT S.date, S.time, S.room, S.floor, S.approver_id
    INTO meeting_date, meeting_time, meeting_room, meeting_floor, meeting_approver_id
    FROM Sessions S
    WHERE S.date = OLD.date AND S.time = OLD.time 
        AND S.room = OLD.room AND S.floor = OLD.floor;

    IF meeting_date < CURRENT_DATE THEN
        RAISE NOTICE 'meeting at % % has passed, unable to leave', meeting_date, meeting_time;
        RETURN NULL;
    ELSE
        IF meeting_date = CURRENT_DATE AND (TIME '00:00:00' + meeting_time * INTERVAL '1 hour') < CURRENT_TIME THEN
            RAISE NOTICE 'meeting at % % has passed, unable to leave', meeting_date, meeting_time;
            RETURN NULL;
        END IF;
    END IF;

    IF meeting_approver_id IS NOT NULL THEN
        RAISE NOTICE 'meeting on % % at floor % room % approved, unable to leave', OLD.date, OLD.time, OLD.floor, OLD.room;
        RETURN NULL;
    END IF;

    RAISE NOTICE 'Employee % left meeting on % % at floor % room %', OLD.eid, OLD.date, OLD.time, OLD.floor, OLD.room;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS employee_leaving ON Joins;
CREATE TRIGGER employee_leaving BEFORE DELETE ON Joins
FOR EACH ROW EXECUTE FUNCTION check_leave_meeting();

--Leave Meeting
CREATE OR REPLACE FUNCTION leave_meeting (employee_id INT, meeting_date DATE, start_hour INT, end_hour INT, floor_num INT, room_num INT)
RETURNS VOID AS $$
DECLARE
BEGIN
    IF start_hour >= end_hour THEN
        RETURN;
    END IF;

    for counter in start_hour..(end_hour-1) LOOP
        DELETE FROM Joins J
        WHERE J.time = counter
            AND J.eid = employee_id AND J.date = meeting_date
            AND J.room = room_num AND J.floor = floor_num;
    END LOOP;
END;

$$ language plpgsql;

-- Approve Meeting Trigger
-- 1. If meeting is not approved (rejected), remove the meeting session
-- 2. Manager can only approve future meetings
-- 3. If manager resigned, cannot approve
-- 4. If meeting already approved, cannot approve again
CREATE OR REPLACE FUNCTION check_approve_meeting()
RETURNS TRIGGER AS $$
DECLARE
    employee_resigned_date DATE;
    meeting_date DATE;
    meeting_time INT;
    meeting_room INT;
    meeting_floor INT;
    meeting_approver_id INT;
BEGIN
    SELECT S.date, S.time, S.room, S.floor, S.approver_id
    INTO meeting_date, meeting_time, meeting_room, meeting_floor, meeting_approver_id
    FROM Sessions S
    WHERE S.date = NEW.date AND S.time = NEW.time 
        AND S.room = NEW.room AND S.floor = NEW.floor;

    IF meeting_date < CURRENT_DATE THEN
        RAISE NOTICE 'meeting at % % has passed, unable to approve', meeting_date, meeting_time;
        RETURN NULL;
    ELSIF meeting_date = CURRENT_DATE AND (TIME '00:00:00' + meeting_time * INTERVAL '1 hour') < CURRENT_TIME THEN
        RAISE NOTICE 'meeting at % % has passed, unable to approve', meeting_time, meeting_date;
        RETURN NULL;
    END IF;

    IF meeting_approver_id IS NOT NULL THEN
        RAISE NOTICE 'meeting on % % at floor % room % already approved, unable to approve again', NEW.date, NEW.time, NEW.floor, NEW.room;
        RETURN NULL;
    END IF;

    SELECT E.resigned_date INTO employee_resigned_date FROM Employees E WHERE E.eid = NEW.approver_id;

    IF employee_resigned_date IS NOT NULL AND employee_resigned_date < meeting_date THEN
        RAISE NOTICE 'employee % already resigned, cannot approve meeting', NEW.approver_id;
        RETURN NULL;
    END IF; 

    RAISE NOTICE 'Manager eid % approved booking for meeting room on % % at floor % room %', NEW.approver_id, NEW.date, NEW.time, NEW.floor, NEW.room;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS approving_meeting ON Sessions;
CREATE TRIGGER approving_meeting BEFORE UPDATE ON Sessions
FOR EACH ROW EXECUTE FUNCTION check_approve_meeting();

-- Approve Meeting
-- 1. Only manager from the same department can approve/reject a meeting
CREATE OR REPLACE FUNCTION approve_meeting (employee_id INT, meeting_date DATE, start_hour INT, end_hour INT, floor_num INT, room_num INT, status CHAR(1))
RETURNS VOID AS $$
DECLARE 
    employee_did INT;
    meeting_room_did INT;
BEGIN
    IF start_hour >= end_hour THEN
        RETURN;
    END IF;

    SELECT E.did INTO employee_did FROM Employees E WHERE E.eid = employee_id;
    SELECT M.did INTO meeting_room_did FROM MeetingRooms M WHERE M.room = room_num AND M.floor = floor_num;

    IF meeting_room_did <> employee_did THEN
        RAISE NOTICE 'Employee and meeting room do not belong to same department, cannot approve/reject meeting';
        RETURN;
    END IF;

    for counter in start_hour..(end_hour-1) LOOP
        IF lower(status) = 'f' THEN
            DELETE FROM Sessions
            WHERE date = meeting_date AND time = counter
                AND room = room_num AND floor = floor_num;
            
            RAISE NOTICE 'Manager eid % from dept % rejected booking for meeting room from dept % on % at floor % room %',
                employee_id, employee_did, meeting_room_did, meeting_date, floor_num, room_num;        
            RAISE NOTICE 'Session removed';
        ELSE
            UPDATE Sessions
            SET approver_id = employee_id
            WHERE date = meeting_date AND time = counter
                AND room = room_num AND floor = floor_num;
        END IF;
    END LOOP;            
END;
$$ LANGUAGE plpgsql;

-- Admin Functions

-- Non-Compliance

CREATE OR REPLACE FUNCTION non_compliance(start_date DATE, end_date DATE)
RETURNS TABLE(employee_id INTEGER, number_of_days INTEGER) AS $$
DECLARE curr_date DATE := start_date;
BEGIN
    -- Date checking if valid
    IF end_date < start_date THEN 
        RAISE EXCEPTION 'End date % is before start date %', end_date, start_date;
    END IF;
    
    -- Creating temporary table to hold employee id values
    DROP TABLE IF EXISTS non_compliant_list;
    CREATE TEMPORARY TABLE non_compliant_list(
        eid INTEGER
    );    

    WHILE curr_date <= end_date LOOP -- dates inclusive
        -- List of employees on this date that do not have a health declaration
        WITH emp_list AS (SELECT DISTINCT E.eid FROM Employees E WHERE E.eid NOT IN (SELECT DISTINCT H.eid FROM HealthDeclaration H WHERE H.date = curr_date))
        -- Insert into temporary table for counting days later
        INSERT INTO non_compliant_list SELECT * FROM emp_list;

        -- Advance loop
        curr_date := curr_date + 1; 
    END LOOP;
    
    -- Selects employee ID and number of days they have not declared temperature
    RETURN QUERY SELECT eid AS employee_id, COUNT(*)::INTEGER AS number_of_days
    FROM non_compliant_list
    GROUP BY eid
    ORDER BY number_of_days DESC, eid ASC;
END;
$$ LANGUAGE plpgsql;

-- View Booking Report
CREATE OR REPLACE FUNCTION view_booking_report(start_date DATE, emp_id INTEGER)
RETURNS TABLE(floor INTEGER, room INTEGER, date DATE, start_hour INTEGER, approved BOOLEAN) AS $$
BEGIN
    IF NOT EXISTS (SELECT * FROM Booker B WHERE B.eid = emp_id) THEN
        RETURN;
    END IF;

    RETURN QUERY SELECT S.floor, S.room, S.date, S.time, S.approver_id IS NOT NULL -- (true if approver id is not null, false if it is null)
    FROM Sessions S
    WHERE S.date >= start_date AND emp_id = S.booker_id
    ORDER BY S.date ASC, S.time ASC;
END;
$$ LANGUAGE plpgsql;


-- View Future Meetings
CREATE OR REPLACE FUNCTION view_future_meeting(start_date DATE, emp_id INTEGER)
RETURNS TABLE(floor INTEGER, room INTEGER, date DATE, start_hour INTEGER) AS $$
BEGIN
    IF NOT EXISTS (SELECT * FROM Employees E WHERE E.eid = emp_id) THEN
        RETURN;
    END IF;

    RETURN QUERY SELECT S.floor, S.room, S.date, S.time 
    -- Check meetings where employee is attending
	FROM Sessions S JOIN Joins J 
    ON S.date = J.date 
       AND S.time = J.time
       AND S.room = J.room 
       AND S.floor = J.floor 
       AND J.eid = emp_id
    -- Check approved meeting from given start date onwards
    WHERE S.approver_id IS NOT NULL AND S.date >= start_date 
    ORDER BY S.date ASC, S.time ASC;
END;
$$ LANGUAGE plpgsql;

-- View Manager Report
-- 1. If the employee ID does not belong to a manager, the routine returns an empty table.
-- 2. Returns a table containing all meeting that are booked but not yet approved from the given start date onwards.
-- 3. Return all meeting in the room with the same department as the manager
-- 4. The table should be sorted in ascending order of date and start hour.
CREATE OR REPLACE FUNCTION view_manager_report(start_date DATE, manager_id INTEGER)
RETURNS TABLE(floor INTEGER, room INTEGER, date DATE, start_hour INTEGER, employee_id INTEGER) AS $$
BEGIN
    IF NOT EXISTS (SELECT * FROM Manager WHERE eid = manager_id) THEN
        RETURN;
    END IF;

    RETURN QUERY SELECT DISTINCT S.floor, S.room, S.date, S.time, S.booker_id
    FROM Sessions S, Employees E, MeetingRooms M
    WHERE S.floor = M.floor AND S.room = M.room
    AND M.did = E.did AND E.did IN (SELECT did FROM Employees WHERE eid = manager_id)
    AND S.approver_id IS NULL AND S.date >= start_date --include start date
    ORDER BY S.date, S.time;
END;
$$ LANGUAGE plpgsql;
