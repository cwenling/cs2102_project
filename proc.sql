-- BASIC FUNCTIONS

--add_department
CREATE OR REPLACE FUNCTION add_department (IN id INT, IN name TEXT) RETURNS VOID AS 
$$
BEGIN
	INSERT INTO Departments (did, dname) VALUES (id, name);

EXCEPTION 
	WHEN unique_violation THEN RAISE EXCEPTION 'This ID already exists!';

END
$$ 
	LANGUAGE plpgsql;


--remove_department
CREATE OR REPLACE FUNCTION warn_department_removal() RETURNS TRIGGER AS
$$
BEGIN 
	RAISE NOTICE 'Department now removed. This cannot be undone!';
	RETURN NEW;
END;
$$ 
	LANGUAGE plpgsql;

CREATE TRIGGER warn_dept_removal
BEFORE UPDATE ON Departments
FOR EACH STATEMENT EXECUTE FUNCTION warn_department_removal();

CREATE OR REPLACE FUNCTION remove_department (IN id INT) RETURNS VOID AS 
$$
BEGIN
	IF id IN (SELECT did FROM Departments) 
		THEN DELETE FROM Departments WHERE did = id;
	ELSE RAISE EXCEPTION USING
		errcode='NODID';
	END IF;

EXCEPTION 
	WHEN sqlstate 'NODID' THEN RAISE EXCEPTION 'This ID does not exist!';
	
END
$$ 
	LANGUAGE plpgsql;


--add_room
-- assumes e_id can legally create the room (no impasta)
CREATE OR REPLACE FUNCTION add_room 
	(IN floornum INT, IN roomnum INT, IN room_name TEXT, IN room_cap INT, IN e_id INT, IN today_date DATE) RETURNS VOID AS 
$$
DECLARE 
	d_id INT;
BEGIN
	SELECT did INTO d_id FROM Employees WHERE eid = e_id;
	INSERT INTO MeetingRooms (floor_num, room_num, rname, did) VALUES (floornum, roomnum, room_name, d_id);
	INSERT INTO Updates (date, new_cap, floor_num, room_num, eid) VALUES (today_date, room_cap, floornum, roomnum, e_id);

EXCEPTION 
	WHEN unique_violation THEN RAISE EXCEPTION 'This meeting room already exists!';

END
$$ 
	LANGUAGE plpgsql;


--change_capacity
-- when adding a new cap, if the new cap, room num, floor num and date alr exists (aka only eid changed),
-- nothing will be updated ie old data entry holds
CREATE OR REPLACE FUNCTION change_capacity 
	(IN floornum INT, IN roomnum INT, IN room_cap INT, IN today_date DATE, IN e_id INT) RETURNS VOID AS 
$$
DECLARE 
	d_id INT;
	room_did INT;
	is_manager BOOLEAN := false;
BEGIN
	SELECT did INTO d_id FROM Employees WHERE eid = e_id;
	SELECT did INTO room_did FROM MeetingRooms WHERE floor_num = floornum AND room_num = roomnum;
	IF e_id IN (SELECT eid FROM Managers) THEN is_manager = true;
	ELSE RAISE EXCEPTION USING 
		errcode='NOTMA';
	END IF;
	IF d_id = room_did THEN 
		IF (today_date, floornum, roomnum) IN (SELECT date, floor_num, room_num FROM Updates) 
			THEN UPDATE Updates
				 SET new_cap = room_cap, eid = e_id
				 WHERE date = today_date AND floor_num = floornum AND room_num = roomnum; 
		ELSE INSERT INTO Updates (date, new_cap, floor_num, room_num, eid) VALUES (today_date, room_cap, floornum, roomnum, e_id);
		END IF;
	ELSE RAISE EXCEPTION USING
		errcode='NOTID';
	END IF;
	
EXCEPTION 
	WHEN sqlstate 'NOTMA' THEN RAISE EXCEPTION 'Only managers can change the room capacity.';
	WHEN sqlstate 'NOTID' THEN RAISE EXCEPTION 'Manager must be from the same department as the room to change its capacity';

	
END
$$ 
	LANGUAGE plpgsql;


--add_employee 
CREATE OR REPLACE FUNCTION add_employee 
	(IN name TEXT, IN home_con INT, IN mobile_con INT, IN office_con INT, IN type TEXT, IN d_id INT) RETURNS VOID AS 
$$
DECLARE 
	e_id INT;
	e_id_str TEXT;
	g_email TEXT;
BEGIN
	SELECT COUNT(*) INTO e_id FROM Employees;	
	e_id = e_id + 1;
	SELECT CAST(e_id AS TEXT) INTO e_id_str;
	SELECT CONCAT(e_id_str, '_', name, '@company.com') INTO g_email;
	
	INSERT INTO Employees VALUES (e_id, name, home_con, mobile_con, office_con, g_email, null, d_id);
	
	IF type = 'junior' THEN 
		INSERT INTO Juniors VALUES (e_id);
	ELSIF type = 'senior' THEN 
		INSERT INTO Bookers VALUES (e_id);
		INSERT INTO Seniors VALUES (e_id);
	ELSIF type = 'manager' THEN 
		INSERT INTO Bookers VALUES (e_id);
		INSERT INTO Managers VALUES (e_id);
	ELSE RAISE EXCEPTION USING
		errcode='INVAL';
	END IF;
	
EXCEPTION 
	WHEN sqlstate 'INVAL' THEN RAISE EXCEPTION 'This employee type does not exist!';
	
END
$$ 
	LANGUAGE plpgsql;

--remove_employee
CREATE OR REPLACE FUNCTION warn_employee_removal() RETURNS TRIGGER AS
$$
BEGIN 
	RAISE NOTICE 'Employee now removed. This cannot be undone!';
	RETURN NEW;
END;
$$ 
	LANGUAGE plpgsql;

CREATE TRIGGER warn_emp_removal
BEFORE UPDATE ON Employees
FOR EACH STATEMENT EXECUTE FUNCTION warn_employee_removal();

CREATE OR REPLACE FUNCTION remove_employee 
	(IN e_id INT, IN date DATE) RETURNS VOID AS 
$$
BEGIN
	IF e_id IN (SELECT eid FROM Employees) THEN
		UPDATE Employees SET res_date = date WHERE eid = e_id;
	ELSE RAISE EXCEPTION USING
		errcode = 'NOEID';
	END IF;

EXCEPTION 
	WHEN sqlstate 'NOEID' THEN RAISE EXCEPTION 'This Employee ID does not exist!';
	
END
$$ 
	LANGUAGE plpgsql;



-- CORE FUNCTIONS

CREATE OR REPLACE FUNCTION search_room
    (IN query_cap INT, IN query_date DATE, IN query_start_hour INT, IN query_end_hour INT)
RETURNS TABLE(floor_num INT, room_num INT, did INT, cap INT) AS $$
BEGIN
    CREATE TEMP TABLE AvailableRooms ON COMMIT DROP AS
    SELECT DISTINCT m.floor_num, m.room_num, m.did
    FROM MeetingRooms m
    WHERE (m.floor_num, m.room_num) NOT IN (
        SELECT s.floor_num, s.room_num
        FROM Sessions s
        WHERE s.date = query_date
        AND s.time BETWEEN query_start_hour AND query_end_hour - 1
    );

    RETURN QUERY
    SELECT a.floor_num, a.room_num, a.did, u.new_cap
    FROM Updates u, AvailableRooms a
    WHERE u.floor_num = a.floor_num
    AND u.room_num = a.room_num
    AND u.new_cap = (SELECT new_cap
                    FROM Updates u2
                    WHERE u2.floor_num = u.floor_num
                    AND u2.room_num = u.room_num
                    AND u2.date <= query_date
                    ORDER BY u2.date DESC -- take the latest updated cap
                    LIMIT 1)
    AND new_cap >= query_cap
    ORDER BY new_cap;
END;
$$ LANGUAGE plpgsql;

-- testcases:
-- when query_eid is a booker, not having fever, room is available for booking (1h) (can book)
-- when query_eid is a booker, not having fever, room is available for booking (> 1h) (can book)
-- when query_eid is not a booker (cannot book)
-- when query_eid is a booker and having fever (cannot book)
-- when query_eid is a booker, not having fever, room is not available for booking (1h) (cannot book)
-- when query_eid is a booker, not having fever, room is not available for booking (> 1h) (cannot book)
CREATE OR REPLACE FUNCTION book_room
    (IN query_floor_num INT, IN query_room_num INT, IN query_date DATE, IN query_start_hour INT, IN query_end_hour INT, IN query_eid INT)
RETURNS VOID AS $$
DECLARE
    today_date DATE := NULL;
    time_diff INT := -1;
    booker_eid INT := -1;
    booker_temp NUMERIC := -1;
    is_room_avail INT := -1;
BEGIN
    IF query_eid NOT IN (SELECT eid FROM Bookers WHERE eid = query_eid)
        THEN RAISE EXCEPTION USING errcode='NOBKR';
    END IF;

    SELECT CURRENT_DATE INTO today_date;
    time_diff := query_end_hour - query_start_hour;
    IF time_diff >= 1 THEN
        SELECT eid INTO booker_eid
        FROM Bookers
        WHERE eid = query_eid;

        SELECT temp INTO booker_temp
        FROM HealthDeclarations
        WHERE eid = booker_eid
        AND date = today_date;

        IF booker_temp <= 37.5 THEN -- has no fever
            SELECT COUNT(*) INTO is_room_avail FROM search_room(1, query_date, query_start_hour, query_end_hour);
            IF is_room_avail <> 0 THEN -- room is avail
                time_diff := query_end_hour - query_start_hour;
                WHILE time_diff >= 1 LOOP
                    INSERT INTO Sessions (time, date, floor_num, room_num, booker_id) VALUES (query_start_hour, query_date, query_floor_num, query_room_num, query_eid);
                    INSERT INTO Joins (eid, time, date, floor_num, room_num) VALUES (booker_eid, query_start_hour, query_date, query_floor_num, query_room_num);
                    query_start_hour := query_start_hour + 1;
                    time_diff := query_end_hour - query_start_hour;
                END LOOP;
            END IF;
        ELSE
            IF booker_temp > 37.5 THEN RAISE EXCEPTION USING errcode='FEVER'; -- having fever
            ELSE RAISE EXCEPTION USING errcode='NODEC'; -- no health declaration today
            END IF;
        END IF;
    END IF;

EXCEPTION
    WHEN sqlstate 'NOBKR' THEN RAISE EXCEPTION 'This ID is not a Booker, cannot book any rooms!';
    WHEN sqlstate 'NODEC' THEN RAISE EXCEPTION 'This Booker has not made any health declaration today, cannot book any rooms!';
    WHEN sqlstate 'FEVER' THEN RAISE EXCEPTION 'This Booker is having a fever, cannot book any rooms!';
    WHEN unique_violation THEN RAISE EXCEPTION 'This room is not available, cannot book!';
END;
$$ LANGUAGE plpgsql;

-- testcases:
-- eid is valid, booking is not approved (can unbook, remove from sessions, remove employees)
-- eid is valid, booking is approved (can unbook, remove from sessions, remove employees)
-- eid is invalid (cannot unbook)
CREATE OR REPLACE FUNCTION unbook_room
    (IN query_floor_num INT, IN query_room_num INT, IN query_date DATE, IN query_start_hour INT, IN query_end_hour INT, IN query_eid INT)
RETURNS VOID AS $$
DECLARE
    temp_query_start_hour INT := query_start_hour;
    booker_eid INT := -1;
    approval_eid INT := -1;
    time_diff INT := -1;
BEGIN
    time_diff := query_end_hour - temp_query_start_hour;
    WHILE time_diff >= 1 LOOP
        IF (query_floor_num, query_room_num, query_date, temp_query_start_hour)
            NOT IN (SELECT floor_num, room_num, date, time
                    FROM Sessions
                    WHERE query_floor_num = floor_num
                    AND query_room_num = room_num
                    AND query_date = date
                    AND temp_query_start_hour = time)
            THEN RAISE EXCEPTION USING errcode='NOEXT';
        END IF;
        temp_query_start_hour := temp_query_start_hour + 1;
        time_diff := query_end_hour - temp_query_start_hour;
    END LOOP;

    temp_query_start_hour := query_start_hour;
    time_diff := query_end_hour - temp_query_start_hour;

    WHILE time_diff >= 1 LOOP
        SELECT booker_id INTO booker_eid
        FROM Sessions
        WHERE floor_num = query_floor_num
        AND room_num = query_room_num
        AND date = query_date
        AND time = temp_query_start_hour;

         -- not the same booker who booked the room from [query_start_hour, query_end_hour)
        IF booker_eid <> query_eid THEN RAISE EXCEPTION USING errcode='NOBKR';
        END IF;

        temp_query_start_hour := temp_query_start_hour + 1;
        time_diff := query_end_hour - temp_query_start_hour;
    END LOOP;

    temp_query_start_hour := query_start_hour;
    time_diff := query_end_hour - temp_query_start_hour;

    IF booker_eid = query_eid THEN
        WHILE time_diff >= 1 LOOP
            SELECT approval_id INTO approval_eid
            FROM Sessions
            WHERE floor_num = query_floor_num
            AND room_num = query_room_num
            AND date = query_date
            AND time = temp_query_start_hour;

            -- remove from Sessions regardless of whether the meeting is approved or not
            -- this will help remove participants from Joins too
            IF approval_eid <> -1 OR approval_eid IS NULL THEN
                DELETE FROM Sessions
                WHERE booker_id = booker_eid
                AND floor_num = query_floor_num
                AND room_num = query_room_num
                AND date = query_date
                AND time = temp_query_start_hour;
            END IF;

            temp_query_start_hour := temp_query_start_hour + 1;
            time_diff := query_end_hour - temp_query_start_hour;
        END LOOP;
    END IF;

EXCEPTION
    WHEN sqlstate 'NOEXT' THEN RAISE EXCEPTION 'There is no booked session for the entire period of time, cannot unbook!';
    WHEN sqlstate 'NOBKR' THEN RAISE EXCEPTION 'This ID is not the Booker for the room, cannot unbook!';
END;
$$ LANGUAGE plpgsql;

-- testcases:
-- eid is not having fever, room is not approved, capacity is enough (can join)
-- eid is not having fever, room is not approved, capacity is not enough (cannot join)
-- eid is not having fever, room is approved (cannot join)
-- eid is having fever (cannot join)
CREATE OR REPLACE FUNCTION join_meeting
    (IN query_floor_num INT, IN query_room_num INT, IN query_date DATE, IN query_start_hour INT, IN query_end_hour INT, IN query_eid INT)
RETURNS VOID AS $$
DECLARE
    temp_query_start_hour INT := query_start_hour;
    today_date DATE := NULL;
    time_diff INT := -1;
    emp_temp NUMERIC := -1;
    approval_eid INT := -1;
    room_cap INT := -1;
    curr_participants INT := -1;
BEGIN
    -- query_eid is still unable to join any meetings as he/she is a close contact
    IF query_date < (SELECT end_date
                    FROM Employees
                    WHERE query_eid = eid)
        THEN RAISE EXCEPTION USING errcode='NJOIN';
    END IF;

    time_diff := query_end_hour - temp_query_start_hour;
    WHILE time_diff >= 1 LOOP
        IF query_eid IN (SELECT eid 
                        FROM Joins
                        WHERE query_floor_num = floor_num
                        AND query_room_num = room_num
                        AND query_date = date
                        AND temp_query_start_hour = time)
            THEN RAISE EXCEPTION USING errcode='BOOKR';
        END IF;

        IF (query_floor_num, query_room_num, query_date, temp_query_start_hour)
            NOT IN (SELECT floor_num, room_num, date, time
                    FROM Sessions
                    WHERE query_floor_num = floor_num
                    AND query_room_num = room_num
                    AND query_date = date
                    AND temp_query_start_hour = time)
            THEN RAISE EXCEPTION USING errcode='NOEXT';
        END IF;

        temp_query_start_hour := temp_query_start_hour + 1;
        time_diff := query_end_hour - temp_query_start_hour;
    END LOOP;

    temp_query_start_hour := query_start_hour;
    time_diff := query_end_hour - temp_query_start_hour;

    SELECT CURRENT_DATE INTO today_date;
    IF time_diff >= 1 THEN
        SELECT temp INTO emp_temp
        FROM HealthDeclarations
        WHERE eid = query_eid
        AND date = today_date;

        IF emp_temp <= 37.5 THEN
            WHILE time_diff >= 1 LOOP
                SELECT approval_id INTO approval_eid
                FROM Sessions
                WHERE floor_num = query_floor_num
                AND room_num = query_room_num
                AND date = query_date
                AND time = temp_query_start_hour;

                IF approval_eid IS NULL THEN
                    SELECT new_cap INTO room_cap
                    FROM Updates
                    WHERE floor_num = query_floor_num
                    AND room_num = query_room_num
                    AND date <= query_date
                    ORDER BY date DESC -- take the latest updated cap
                    LIMIT 1;

                    SELECT COUNT(*) INTO curr_participants
                    FROM Joins
                    WHERE floor_num = query_floor_num
                    AND room_num = query_room_num
                    AND date = query_date
                    AND time = temp_query_start_hour;

                    IF room_cap - curr_participants > 0 THEN
                        INSERT INTO Joins (eid, time, date, floor_num, room_num) VALUES (query_eid, temp_query_start_hour, query_date, query_floor_num, query_room_num);
                    ELSE RAISE EXCEPTION USING errcode='NOCAP';
                    END IF;
                ELSE RAISE EXCEPTION USING errcode='APPRV';
                END IF;

                temp_query_start_hour := temp_query_start_hour + 1;
                time_diff := query_end_hour - temp_query_start_hour;
            END LOOP;
        ELSE
            IF emp_temp > 37.5 THEN RAISE EXCEPTION USING errcode='FEVER';
            ELSE RAISE EXCEPTION USING errcode='NODEC';
            END IF;
        END IF;
    END IF;

EXCEPTION
    WHEN sqlstate 'NJOIN' THEN RAISE EXCEPTION 'This ID is still being contact traced, cannot join any rooms!';
    WHEN sqlstate 'BOOKR' THEN RAISE EXCEPTION 'This ID is the Booker for the meeting, already joined!';
    WHEN sqlstate 'NOEXT' THEN RAISE EXCEPTION 'There is no booked session for the entire period of time, cannot join!';
    WHEN sqlstate 'NOCAP' THEN RAISE EXCEPTION 'There is not enough capacity, cannot join!';
    WHEN sqlstate 'APPRV' THEN RAISE EXCEPTION 'The meeting is already approved, cannot join!';
    WHEN sqlstate 'FEVER' THEN RAISE EXCEPTION 'This ID is having a fever, cannot join any rooms!';
    WHEN sqlstate 'NODEC' THEN RAISE EXCEPTION 'This ID has not made any health declaration today, cannot join any rooms!';
END;
$$ LANGUAGE plpgsql;

-- testcases:
-- eid is not in meeting (don't do anything)
-- eid is in meeting, meeting is not approved (can leave)
-- eid is in meeting, meeting is approved (cannot leave)
CREATE OR REPLACE FUNCTION leave_meeting
    (IN query_floor_num INT, IN query_room_num INT, IN query_date DATE, IN query_start_hour INT, IN query_end_hour INT, IN query_eid INT)
RETURNS VOID AS $$
DECLARE
    temp_query_start_hour INT := query_start_hour;
    time_diff INT := -1;
    is_in_meeting INT := -1;
    approval_eid INT := -1;
    is_booker INT := -1;
BEGIN
    time_diff := query_end_hour - temp_query_start_hour;
    WHILE time_diff >= 1 LOOP
        IF (query_floor_num, query_room_num, query_date, temp_query_start_hour)
            NOT IN (SELECT floor_num, room_num, date, time
                    FROM Sessions
                    WHERE query_floor_num = floor_num
                    AND query_room_num = room_num
                    AND query_date = date
                    AND temp_query_start_hour = time)
            THEN RAISE EXCEPTION USING errcode='NOEXT';
        END IF;
        temp_query_start_hour := temp_query_start_hour + 1;
        time_diff := query_end_hour - temp_query_start_hour;
    END LOOP;

    temp_query_start_hour := query_start_hour;
    time_diff := query_end_hour - temp_query_start_hour;

    WHILE time_diff >= 1 LOOP
        SELECT COUNT(*) INTO is_in_meeting
        FROM Joins
        WHERE eid = query_eid
        AND floor_num = query_floor_num
        AND room_num = query_room_num
        AND date = query_date
        AND time = temp_query_start_hour;

        SELECT COUNT(*) INTO is_booker
        FROM Sessions
        WHERE floor_num = query_floor_num
        AND room_num = query_room_num
        AND date = query_date
        AND time = temp_query_start_hour
        AND booker_id = query_eid;

        IF is_in_meeting > 0 THEN
            SELECT approval_id INTO approval_eid
            FROM Sessions
            WHERE floor_num = query_floor_num
            AND room_num = query_room_num
            AND date = query_date
            AND time = temp_query_start_hour;

            IF approval_eid IS NULL THEN
                IF is_booker == 1 THEN -- the booker is leaving the meeting, so need to remove the Sessions, which will then remove employees from Joins
                    DELETE FROM Sessions
                    WHERE floor_num = query_floor_num
                    AND room_num = query_room_num
                    AND date = query_date
                    AND time = temp_query_start_hour;
                ELSE
                    DELETE FROM Joins
                    WHERE eid = query_eid
                    AND floor_num = query_floor_num
                    AND room_num = query_room_num
                    AND date = query_date
                    AND time = temp_query_start_hour;
                END IF;
            ELSE RAISE EXCEPTION USING errcode='APPRV';
            END IF;
        ELSE RAISE EXCEPTION USING errcode='NOMTG';
        END IF;
        temp_query_start_hour := temp_query_start_hour + 1;
        time_diff := query_end_hour - temp_query_start_hour;
    END LOOP;

EXCEPTION
    WHEN sqlstate 'NOEXT' THEN RAISE EXCEPTION 'There is no booked session for the entire period of time, cannot leave!';
    WHEN sqlstate 'APPRV' THEN RAISE EXCEPTION 'The meeting is already approved, cannot leave!';
    WHEN sqlstate 'NOMTG' THEN RAISE EXCEPTION 'This ID is not in the meeting, not leaving!';
END;
$$ LANGUAGE plpgsql;

-- testcases:
-- eid is manager, room belongs to same department as manager (can approve)
-- eid is manager, room belongs to different department as manager (cannot approve)
-- eid is not a manager (cannot approve)

-- is_approved flag to tell if manager approves or not - if not approved, the booking will be removed from Sessions
CREATE OR REPLACE FUNCTION approve_meeting
    (IN query_floor_num INT, IN query_room_num INT, IN query_date DATE, IN query_start_hour INT, IN query_end_hour INT, IN query_eid INT, IN is_approve BOOLEAN)
RETURNS VOID AS $$
DECLARE
    temp_query_start_hour INT := query_start_hour;
    time_diff INT := -1;
    manager_eid INT := -1;
    manager_did INT := -1;
    room_did INT := -1;
BEGIN
    IF query_eid NOT IN (SELECT eid FROM Managers WHERE eid = query_eid)
        THEN RAISE EXCEPTION USING errcode='NOMAN';
    END IF;

    time_diff := query_end_hour - temp_query_start_hour;
    WHILE time_diff >= 1 LOOP
        IF (query_floor_num, query_room_num, query_date, temp_query_start_hour)
            NOT IN (SELECT floor_num, room_num, date, time
                    FROM Sessions
                    WHERE query_floor_num = floor_num
                    AND query_room_num = room_num
                    AND query_date = date
                    AND temp_query_start_hour = time)
            THEN RAISE EXCEPTION USING errcode='NOEXT';
        END IF;
        temp_query_start_hour := temp_query_start_hour + 1;
        time_diff := query_end_hour - temp_query_start_hour;
    END LOOP;

    temp_query_start_hour := query_start_hour;
    time_diff := query_end_hour - temp_query_start_hour;

    WHILE time_diff >= 1 LOOP
        SELECT eid INTO manager_eid
        FROM Managers
        WHERE eid = query_eid;

        IF manager_eid <> -1 THEN -- is a manager
            SELECT did INTO manager_did
            FROM Employees
            WHERE eid = manager_eid;

            SELECT did INTO room_did
            FROM MeetingRooms
            WHERE floor_num = query_floor_num
            AND room_num = query_room_num;

            IF manager_did = room_did THEN -- room same department as manager
                IF is_approve == 'f' THEN -- manager does not want to approve meeting
                    SELECT * FROM remove_meeting(query_floor_num, query_room_num, query_date, query_start_hour);
                ELSE
                    UPDATE Sessions
                    SET approval_id = manager_eid
                    WHERE floor_num = query_floor_num
                    AND room_num = query_room_num
                    AND date = query_date
                    AND time = temp_query_start_hour;
                END IF;
            ELSE RAISE EXCEPTION USING errcode='NODID';
            END IF;
        END IF;
        temp_query_start_hour := temp_query_start_hour + 1;
        time_diff := query_end_hour - temp_query_start_hour;
    END LOOP;

EXCEPTION
    WHEN sqlstate 'NOMAN' THEN RAISE EXCEPTION 'This ID is not a Manager, cannot approve any meetings!';
    WHEN sqlstate 'NOEXT' THEN RAISE EXCEPTION 'There is no booked session for the entire period of time, cannot approve!';
    WHEN sqlstate 'NODID' THEN RAISE EXCEPTION 'This Manager does not belong to the same department as the meeting room, cannot approve!';
END;
$$ LANGUAGE plpgsql;

-- this function helps to remove any booking which is not approved by any managers so other people can book the meeting room
CREATE OR REPLACE FUNCTION remove_meeting
    (IN query_floor_num INT, IN query_room_num INT, IN query_date DATE, IN query_start_hour INT)
RETURNS VOID AS $$
BEGIN
    DELETE FROM Sessions
    WHERE floor_num = query_floor_num
    AND room_num = query_room_num
    AND date = query_date
    AND time = query_start_hour;
END;
$$ LANGUAGE plpgsql;



-- HEALTH FUNCTIONS
--declare_health
DROP FUNCTION declare_health(integer,date,numeric);
CREATE OR REPLACE FUNCTION declare_health (IN input_id INT, IN input_date DATE, IN input_temp NUMERIC) RETURNS VOID AS 
$$
BEGIN
    IF input_id IN (SELECT eid FROM Employees)
        INSERT INTO HealthDeclarations (date, temp, eid) VALUES (input_date, input_temp, input_id);
    ELSE RAISE EXCEPTION USING
        errcode='NOEID';
    END IF;

EXCEPTION
    WHEN sqlstate 'NOEID' THEN RAISE EXCEPTION 'This ID does not exist!';
END
$$ 
	LANGUAGE plpgsql;

--contact_tracing, returns table of close contacts to employee id.
DROP FUNCTION contact_tracing(integer);
CREATE OR REPLACE FUNCTION contact_tracing (IN traced_id INT) RETURNS TABLE(eid INT) AS 
$$
DECLARE
    declared_date DATE;
    declared_temp NUMERIC;
    declared_time INTEGER;
    declared_id INTEGER := traced_id;
BEGIN
    SELECT max(date) INTO declared_date FROM HealthDeclarations hd WHERE hd.eid = declared_id;
    SELECT temp INTO declared_temp FROM HealthDeclarations hd WHERE hd.eid = declared_id AND date = declared_date;
    SELECT EXTRACT(HOUR FROM localtime) INTO declared_time FROM NOW();
    IF declared_temp > 37.5 THEN
        CREATE VIEW close_contacts AS
            (SELECT j2.eid
            FROM Joins j1, Joins j2, Sessions s
            WHERE j1.eid = declared_id
            AND s.approval_id IS NOT NULL
            AND s.date >= declared_date - 3
            AND s.date < declared_date
            AND j1.time = s.time
            AND j1.date = s.date
            AND j1.floor_num = s.floor_num
            AND j1.room_num = s.room_num
            AND j2.time = s.time
            AND j2.date = s.date
            AND j2.floor_num = s.floor_num
            AND j2.room_num = s.room_num)
            UNION
            (SELECT j2.eid
            FROM Joins j1, Joins j2, Sessions s
            WHERE j1.eid = declared_id
            AND s.approval_id IS NOT NULL
            AND s.date = declared_date
            AND j2.time <= declared_time
            AND j1.time = s.time
            AND j1.date = s.date
            AND j1.floor_num = s.floor_num
            AND j1.room_num = s.room_num
            AND j2.time = s.time
            AND j2.date = s.date
            AND j2.floor_num = s.floor_num
            AND j2.room_num = s.room_num);

        DELETE FROM Joins WHERE ((date > declared_date) OR (date = declared_date AND time > declared_time))  AND eid = declared_id;
        DELETE FROM Sessions WHERE ((date > declared_date) OR (date = declared_date AND time > declared_time)) AND booker_id = declared_id;

        DELETE FROM Joins WHERE eid IN (close_contacts) AND ((date > declared_date) OR (date = declared_date AND time > declared_time)) AND date <= declared_date + 7;
        UPDATE Employees SET end_date = declared_date + 7;
        RETURN QUERY SELECT * FROM close_contacts;
    END IF;
END
$$ 
	LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS cannot_modify_health_declaration on HealthDeclarations;
CREATE TRIGGER IF EXISTS cannot_modify_health_declaration
BEFORE UPDATE OR DELETE ON HealthDeclarations
FOR EACH STATEMENT
EXECUTE FUNCTION prevent_modification();

CREATE OR REPLACE FUNCTION prevent_modification() RETURNS TRIGGER AS 
$$
BEGIN
    RETURN NULL;
END
$$ 
	LANGUAGE plpgsql;

DROP TRIGGER IF exists contact_trace_if_fever on HealthDeclarations;
CREATE TRIGGER contact_trace_if_fever
AFTER INSERT ON HealthDeclarations
FOR EACH ROW WHEN (NEW.temp > 37.5)
EXECUTE FUNCTION contact_trace();

CREATE OR REPLACE FUNCTION contact_trace () RETURNS TRIGGER AS 
$$
BEGIN
    SELECT * FROM contact_tracing(NEW.eid);
    RETURN NULL;
END
$$ 
	LANGUAGE plpgsql;



-- ADMIN FUNCTIONS

/* Employees checked from start_date to 
end_date/res_date, whichever is earlier. */
CREATE OR REPLACE FUNCTION non_compliance
    (IN _start_date DATE, IN _end_date DATE)
RETURNS TABLE(eid INT, days_recorded BIGINT) AS $$
BEGIN
    -- Health declarations in the future should not exist
    IF _start_date > CURRENT_DATE OR _end_date > CURRENT_DATE OR (_start_date > _end_date) 
        THEN RAISE EXCEPTION USING errcode = 'NODTE';
    END IF;

    CREATE TEMP TABLE validDurations ON COMMIT DROP AS
    SELECT e.eid, (CASE 
        WHEN e.res_date IS NOT NULL AND e.res_date < _end_date THEN e.res_date
        ELSE _end_date
    END) - _start_date AS duration
    FROM Employees e;
    
    RETURN QUERY
    SELECT hd.eid, hd.duration - COUNT(DISTINCT hd.date) AS missedDays  
    FROM (HealthDeclarations NATURAL JOIN Employees NATURAL JOIN validDurations) AS hd
    WHERE date BETWEEN _start_date 
    AND _start_date + hd.duration
    GROUP BY hd.eid, hd.duration
    HAVING COUNT(DISTINCT hd.date) < hd.duration
    ORDER BY missedDays DESC;

EXCEPTION
    WHEN sqlstate 'NODTE' THEN RAISE EXCEPTION 'The specified date range is invalid.';
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION view_booking_report
    (IN _start_date DATE, IN _eid INT)
RETURNS TABLE(floor_num INT, room_num INT, date DATE, start_hour INT, is_approved BOOLEAN) AS $$
BEGIN
    IF _eid NOT IN (SELECT eid FROM Bookers)  
    THEN RAISE EXCEPTION USING errcode='NOBKR';
    END IF;

    RETURN QUERY
    SELECT DISTINCT s.floor_num, s.room_num, s.date, s.time, s.approval_id IS NOT NULL AS is_approved
    FROM Sessions s
    WHERE s.booker_id = _eid AND s.date >= _start_date
    GROUP BY s.floor_num, s.room_num, s.date, s.time
    ORDER BY s.date, s.time ASC;

EXCEPTION
    WHEN sqlstate 'NOBKR' THEN RAISE EXCEPTION 'The specified employee has no booking privileges.';
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION view_future_meeting
    (IN _start_date DATE, IN _eid INT)
RETURNS TABLE(floor_num INT, room_num INT, date DATE, start_hour INT) AS $$
BEGIN
    IF _start_date < CURRENT_DATE 
        THEN RAISE EXCEPTION USING errcode='NODTE';
    END IF;

    RETURN QUERY
    SELECT DISTINCT sj.floor_num, sj.room_num, sj.date, sj.time
    FROM (Sessions NATURAL JOIN Joins) AS sj
    WHERE sj.eid = _eid AND sj.date >= _start_date AND sj.approval_id IS NOT NULL
    GROUP BY sj.floor_num, sj.room_num, sj.date, sj.time
    ORDER BY sj.date, sj.time ASC;

EXCEPTION
    WHEN sqlstate 'NODTE' THEN RAISE EXCEPTION 'The specified start date should be today''s date or later.';
END;
$$ LANGUAGE plpgsql;

-- eid refers to manager id
CREATE OR REPLACE FUNCTION view_manager_report
    (IN _start_date DATE, IN _eid INT)
RETURNS TABLE(floor_num INT, room_num INT, date DATE, start_hour INT, eid INT) AS $$
BEGIN
    -- Shouldn't return meetings that have already passed
    IF _start_date < CURRENT_DATE 
        THEN RAISE EXCEPTION USING errcode = 'NODTE';
    END IF;

    RETURN QUERY
    SELECT DISTINCT m.floor_num, m.room_num, m.date, m.time, m.eid
    FROM (Departments NATURAL JOIN Employees NATURAL JOIN Managers NATURAL JOIN MeetingRooms NATURAL JOIN Sessions) as m 
    WHERE m.eid =  _eid AND m.approval_id IS NULL AND m.date >= _start_date
    GROUP BY m.floor_num, m.room_num, m.date, m.time, m.eid
    ORDER BY m.date, m.time ASC;

EXCEPTION
    WHEN sqlstate 'NODTE' THEN RAISE EXCEPTION 'The specified start date should be today''s date or later.';
END;
$$ LANGUAGE plpgsql;
