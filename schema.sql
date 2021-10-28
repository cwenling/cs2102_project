DROP TABLE IF EXISTS Employees, Juniors, Bookers, Seniors, Managers, Departments, MeetingRooms,Updates, HealthDeclarations, Sessions, Joins CASCADE;

CREATE TABLE Departments (
    did          INTEGER PRIMARY KEY,
    dname        TEXT
);

CREATE TABLE Employees (
    eid           INTEGER PRIMARY KEY,
    ename         TEXT,
    home_num      INTEGER,
    mobile_num	  INTEGER,
    office_num    INTEGER,
    email         TEXT UNIQUE NOT NULL,
    res_date      DATE,
    did           INTEGER,
    end_date      DATE,
    FOREIGN KEY (did) REFERENCES Departments (did) ON DELETE SET NULL ON UPDATE CASCADE
);

CREATE TABLE Juniors (
    eid        INTEGER PRIMARY KEY,
    FOREIGN KEY (eid) REFERENCES Employees (eid) ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE Bookers (
    eid        INTEGER PRIMARY KEY,
    FOREIGN KEY (eid) REFERENCES Employees (eid) ON DELETE CASCADE ON UPDATE CASCADE 
);

CREATE TABLE Seniors (
    eid		INTEGER PRIMARY KEY,
    FOREIGN KEY (eid) REFERENCES Bookers (eid) ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE Managers (
    eid         INTEGER PRIMARY KEY,
    FOREIGN KEY (eid) REFERENCES Bookers (eid) ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE MeetingRooms (
    floor_num    INTEGER,
    room_num     INTEGER,
    rname        TEXT,
    did          INTEGER,
    PRIMARY KEY (floor_num, room_num),
    FOREIGN KEY (did) REFERENCES Departments (did) ON DELETE SET NULL ON UPDATE CASCADE
);

-- eid refers to the manager’s eid
CREATE TABLE Updates (
    date            DATE,
    new_cap         INTEGER CHECK (new_cap >= 0),
    floor_num       INTEGER,
    room_num        INTEGER,
    eid             INTEGER NOT NULL,
    PRIMARY KEY (date, floor_num, room_num),
    FOREIGN KEY (floor_num, room_num) REFERENCES MeetingRooms (floor_num, room_num),
    FOREIGN KEY (eid) REFERENCES Managers (eid)
);

CREATE TABLE HealthDeclarations (
    date        DATE,
    temp        NUMERIC NOT NULL CHECK (temp >= 34 AND temp <= 43),
    eid         INTEGER,
    PRIMARY KEY (eid, date),
    FOREIGN KEY (eid) REFERENCES Employees (eid)
);

CREATE TABLE Sessions (
    time         INTEGER,
    date         DATE,
    floor_num    INTEGER,
    room_num     INTEGER,
    booker_id    INTEGER NOT NULL,
    approval_id  INTEGER DEFAULT NULL,
    PRIMARY KEY (time, date, floor_num, room_num),
    FOREIGN KEY (floor_num, room_num) REFERENCES MeetingRooms (floor_num, room_num),
    FOREIGN KEY (booker_id) REFERENCES Bookers (eid),
    FOREIGN KEY (approval_id) REFERENCES Managers (eid)
);

CREATE TABLE Joins (
    eid          INTEGER,
    time         INTEGER,
    date         DATE,
    floor_num    INTEGER,
    room_num     INTEGER,
    PRIMARY KEY (eid, time, date, floor_num, room_num),
    FOREIGN KEY (time, date, floor_num, room_num) 
        REFERENCES Sessions (time, date, floor_num, room_num) ON DELETE CASCADE,
    FOREIGN KEY (eid) REFERENCES Employees (eid)
);
