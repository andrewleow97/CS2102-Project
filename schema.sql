-- SCHEMA SQL to CREATE TABLE database schema
DROP TABLE IF EXISTS Employees, Junior, Senior, Manager, Booker, Joins, Sessions, Updates, MeetingRooms, Departments, HealthDeclaration;

CREATE TABLE Departments (
    did INTEGER PRIMARY KEY,
    dname TEXT NOT NULL 
);

CREATE TABLE Employees (
    eid INTEGER PRIMARY KEY,
    did INTEGER NOT NULL,
    ename TEXT NOT NULL,
    email TEXT UNIQUE,
    home_phone INTEGER UNIQUE,
    mobile_phone INTEGER UNIQUE,
    office_phone INTEGER UNIQUE,
    resigned_date DATE,
    FOREIGN KEY (did) REFERENCES Departments (did)
);

CREATE TABLE Junior (
    eid INTEGER PRIMARY KEY,
    FOREIGN KEY (eid) REFERENCES Employees (eid) ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE Booker (
    eid INTEGER PRIMARY KEY,
    FOREIGN KEY (eid) REFERENCES Employees (eid) ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE Senior (
    eid INTEGER PRIMARY KEY,
    FOREIGN KEY (eid) REFERENCES Booker (eid) ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE Manager (
    eid INTEGER PRIMARY KEY,
    FOREIGN KEY (eid) REFERENCES Booker (eid) ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE MeetingRooms (
    room_number INTEGER,
    floor INTEGER,
    rname TEXT NOT NULL,
    did INTEGER NOT NULL,
    PRIMARY KEY (room_number, floor),
    FOREIGN KEY (did) REFERENCES Departments (did)
);

CREATE TABLE Sessions (
    date DATE,
    time TIME,
    room INTEGER,
    floor INTEGER,
    booker_id INTEGER NOT NULL,
    approver_id INTEGER,
    PRIMARY KEY (date, time, room, floor),
    FOREIGN KEY (room, floor) REFERENCES MeetingRooms (room_number, floor) ON DELETE CASCADE,
    FOREIGN KEY (booker_id) REFERENCES Booker (eid),
    FOREIGN KEY (approver_id) REFERENCES Manager (eid)
);

CREATE TABLE Joins (
    eid INTEGER,
    date DATE,
    time TIME,
    room INTEGER NOT NULL,
    floor INTEGER NOT NULL,
    PRIMARY KEY (eid, date, time),
    FOREIGN KEY (date, time, room, floor) REFERENCES Sessions (date, time, room, floor) ON DELETE CASCADE,
    FOREIGN KEY (eid) REFERENCES Employees (eid) ON DELETE CASCADE
);

CREATE TABLE HealthDeclaration (
    eid INTEGER,
    date DATE,
    temperature NUMERIC NOT NULL CHECK (temperature >= 34 AND temperature <= 43),
    fever boolean NOT NULL,
    PRIMARY KEY (eid, date),
    FOREIGN KEY (eid) REFERENCES Employees (eid) ON DELETE CASCADE
);

CREATE TABLE Updates (
    date DATE,
    new_capacity INTEGER,
    room_number INTEGER,
    floor INTEGER,
    manager_id INTEGER,
    PRIMARY KEY (date, room_number, floor, manager_id),
    FOREIGN KEY (room_number, floor) REFERENCES MeetingRooms(room_number, floor),
    FOREIGN KEY (manager_id) REFERENCES Manager (eid)
);
