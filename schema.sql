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
    FOREIGN KEY (did) REFERENCES Departments (did) ON UPDATE CASCADE
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
    floor INTEGER,
    room INTEGER,
    rname TEXT NOT NULL,
    did INTEGER NOT NULL,
    PRIMARY KEY (floor, room),
    FOREIGN KEY (did) REFERENCES Departments (did) ON UPDATE CASCADE
);

CREATE TABLE Sessions (
    date DATE,
    time INTEGER,
    floor INTEGER,
    room INTEGER,
    booker_id INTEGER NOT NULL,
    approver_id INTEGER,
    PRIMARY KEY (date, time, floor, room),
    FOREIGN KEY (floor, room) REFERENCES MeetingRooms (floor, room) ON DELETE CASCADE,
    FOREIGN KEY (booker_id) REFERENCES Booker (eid),
    FOREIGN KEY (approver_id) REFERENCES Manager (eid)
);

CREATE TABLE Joins (
    eid INTEGER,
    date DATE,
    time INTEGER,
    floor INTEGER NOT NULL,
    room INTEGER NOT NULL,
    PRIMARY KEY (eid, date, time),
    FOREIGN KEY (date, time, floor, room) REFERENCES Sessions (date, time, floor, room) ON DELETE CASCADE,
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
    new_capacity INTEGER NOT NULL DEFAULT 20,
    floor INTEGER,
    room INTEGER,
    eid INTEGER,
    PRIMARY KEY (date, floor, room),
    FOREIGN KEY (floor, room) REFERENCES MeetingRooms(floor, room),
    FOREIGN KEY (eid) REFERENCES Manager (eid)
);
