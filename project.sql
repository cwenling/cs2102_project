CREATE TABLE Employees (
emp_id    INTEGER PRIMARY KEY,
ename        TEXT,
phone_num    INTEGER,
email         TEXT UNIQUE NOT NULL,
dept_id    INTEGER,
FOREIGN KEY (dept_id) REFERENCES Departments (dept_id)
);

CREATE TABLE Managers (
    emp_id     INTEGER PRIMARY KEY,
    approval_ban     BOOLEAN DEFAULT False,
    booking_ban     BOOLEAN DEFAULT False,
    FOREIGN KEY (emp_id) REFERENCES Employees (emp_id)
);

CREATE TABLE Juniors (
    emp_id    INTEGER PRIMARY KEY,
    FOREIGN KEY (emp_id) REFERENCES Employees (emp_id)
);

CREATE TABLE Seniors (
    emp_id     INTEGER PRIMARY KEY,
    booking_ban    BOOLEAN DEFAULT False,
FOREIGN KEY (emp_id) REFERENCES Employees (emp_id)
);

CREATE TABLE Departments (
    dept_id      INTEGER PRIMARY KEY,
    dname        TEXT
);

CREATE TABLE HealthDeclarations (
    date        DATE,
    temperature    NUMERIC,
    emp_id    INTEGER,
    PRIMARY KEY (emp_id, date),
    FOREIGN KEY (emp_id) REFERENCES Employees (emp_id)
);

CREATE TABLE Bookings (
    b_id        INTEGER PRIMARY KEY,
    floor_num    INTEGER,
    room_num     INTEGER,
    date         DATE,
    start_hour     TIME,
    end_hour     TIME,
    is_approved     BOOLEAN DEFAULT False,
    UNIQUE (date, start_hour, end_hour, floor_num, room_num),
    FOREIGN KEY (floor_num, room_num) REFERENCES MeetingRooms (floor_num, room_num),
    CHECK (end_hour - start_hour = 1)
);

CREATE TABLE Participants (
    emp_id    INTEGER,
    b_id         INTEGER,
    PRIMARY KEY (emp_id, b_id),
    FOREIGN KEY (emp_id) REFERENCES Employees (emp_id),
    FOREIGN KEY (b_id) REFERENCES Bookings (b_id)
);

CREATE TABLE MeetingRooms (
    rname         TEXT,
    floor_num     INTEGER,
room_num     INTEGER,
    max_capacity     INTEGER NOT NULL, 
    dept_id     INTEGER,
    PRIMARY KEY (floor_num, room_num),
    FOREIGN KEY (dept_id) REFERENCES Departments (dept_id)
);
