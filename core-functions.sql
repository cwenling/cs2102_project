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

        IF is_in_meeting > 0 THEN
            SELECT approval_id INTO approval_eid
            FROM Sessions
            WHERE floor_num = query_floor_num
            AND room_num = query_room_num
            AND date = query_date
            AND time = temp_query_start_hour;

            IF approval_eid IS NULL THEN
                DELETE FROM Joins
                WHERE eid = query_eid
                AND floor_num = query_floor_num
                AND room_num = query_room_num
                AND date = query_date
                AND time = temp_query_start_hour;
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
CREATE OR REPLACE FUNCTION approve_meeting
    (IN query_floor_num INT, IN query_room_num INT, IN query_date DATE, IN query_start_hour INT, IN query_end_hour INT, IN query_eid INT)
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
                UPDATE Sessions
                SET approval_id = manager_eid
                WHERE floor_num = query_floor_num
                AND room_num = query_room_num
                AND date = query_date
                AND time = temp_query_start_hour;
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
