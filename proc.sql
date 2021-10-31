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