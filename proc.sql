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