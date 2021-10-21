-- search_room
-- - returns all rooms available from [start_hour, end_hour)
-- - sort in ascending order of capacity
-- available = does not appear in Sessions (booker_id not null)

-- testcases to test:
-- room is available
-- room is unavailable
CREATE OR REPLACE FUNCTION search_room
    (IN query_cap INT, IN query_date DATE, IN query_start_hour INT, IN query_end_hour INT)
RETURNS TABLE(out_floor_num INT, out_room_num INT, out_did INT, out_cap INT) AS $$
DECLARE
    room_cap INT := -1;
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
    
    SELECT floor_num, room_num, did
    INTO out_floor_num, out_room_num, out_did
    FROM AvailableRooms;

    SELECT new_cap
    INTO out_cap
    FROM Updates u, AvailableRooms a
    WHERE u.floor_num = a.floor_num
    AND u.room_num = a.room_num
    AND new_cap = (SELECT new_cap
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

-- book_room
-- - A senior employee or a manager books a room by specifying the room and the session.
-- - If the room is not available for the given session, no booking can be done.
-- - If the employee is having a fever, they cannot book any room.
-- assumptions made:
-- query_eid can only book a room on query_date, from [query_start_hour, query_end_hour) only if:
-- 1. query_eid is a booker
-- 2. query_eid is not having a fever
-- 3. a room is available on query_date, from [query_start_hour, query_end_hour)

-- TODO CANNOT TEST UNTIL SEARCH_ROOM IS OK

-- testcases to test:
-- when query_eid is a booker, not having fever, room is available for booking (1h) (can book)
-- book_room(1, 1, '2021-10-20', 12, 13, 51)

-- when query_eid is a booker, not having fever, room is available for booking (> 1h) (can book)
-- book_room(1, 1, '2021-10-21', 12, 15, 51)

-- when query_eid is not a booker (cannot book)
-- book_room(1, 1, '2021-10-21', 12, 15, 1)

-- when query_eid is a booker and having fever (cannot book)
-- book_room(1, 1, '2021-10-21', 12, 15, 52)

-- when query_eid is a booker, not having fever, room is not available for booking (1h) (cannot book)
-- book_room(1, 4, '2021-10-13', 0, 1, 51)

-- when query_eid is a booker, not having fever, room is not available for booking (> 1h) (cannot book)
-- book_room(1, 4, '2021-10-13', 0, 1, 51)
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
    SELECT CURRENT_DATE INTO today_date;
    time_diff := query_end_hour - query_start_hour;
    IF time_diff >= 1 THEN
        SELECT eid INTO booker_eid
        FROM Bookers
        WHERE eid = query_eid;

        IF booker_eid <> -1 THEN -- is a booker
            SELECT temp INTO booker_temp
            FROM HealthDeclarations
            WHERE eid = booker_eid
            AND date = today_date;

            IF booker_temp <= 37.5 THEN -- has no fever
                SELECT COUNT(*) INTO is_room_avail FROM search_room(1, query_date, query_start_hour, query_end_hour);

                IF is_room_avail <> -1 THEN -- room is avail
                    time_diff := query_end_hour - query_start_hour;
                    WHILE time_diff >= 1 LOOP
                        INSERT INTO Sessions (time, date, floor_num, room_num, booker_id) VALUES (query_start_hour, query_date, query_floor_num, query_room_num, query_eid);
                        query_start_hour := query_start_hour + 1;
                        time_diff := query_end_hour - query_start_hour;
                    END LOOP;
                END IF;
            END IF;
        END IF;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- unbook_room
-- assumptions made:
-- this function is to unbook a meeting room on query_date, from [query_start_hour, query_end_hour) and on query_date only made by query_eid
-- for example if the query is [10am, 12pm),
-- and if query_eid only made a booking from [10am, 11am) OR query_eid made a booking from [10am, 1pm), this room will not be unbooked
-- but if query_eid made a booking from [10am, 12pm), this room will be unbooked
-- once a room is unbooked, it is removed from Sessions table

-- ALL TESTED EXCEPT >1H
-- testcases to test:
-- eid is valid, booking is not approved (can unbook, remove from sessions, remove employees)
-- unbook_room(2, 7, '2021-10-15', 2, 3, 91)

-- eid is valid, booking is approved (can unbook, remove from sessions, remove employees)
-- unbook_room(2, 3, '2021-10-14', 10, 11, 81)

-- eid is invalid (cannot unbook)
-- unbook_room(2, 3, '2021-10-14', 10, 11, 82)
CREATE OR REPLACE FUNCTION unbook_room
    (IN query_floor_num INT, IN query_room_num INT, IN query_date DATE, IN query_start_hour INT, IN query_end_hour INT, IN query_eid INT)
RETURNS VOID AS $$
DECLARE
    temp_query_start_hour INT := query_start_hour;
    booker_eid INT := -1;
    approval_eid INT := -1;
    time_diff INT := -1;
BEGIN
    -- check if it is the same booker from [query_start_hour, query_end_hour)
    -- if it is not, don't allow query_eid to unbook
    time_diff := query_end_hour - temp_query_start_hour;
    WHILE time_diff >= 1 LOOP
        SELECT booker_id INTO booker_eid
        FROM Sessions
        WHERE floor_num = query_floor_num
        AND room_num = query_room_num
        AND date = query_date
        AND time = temp_query_start_hour;

        IF booker_eid <> query_eid THEN -- not the same booker who booked the room from [query_start_hour, query_end_hour)
            booker_eid := -1;
            EXIT;
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
END;
$$ LANGUAGE plpgsql;

-- ALL TESTED EXCEPT FOR >1H
-- testcases to test:
-- eid is not having fever, room is not approved, capacity is enough (can join)
-- join_meeting(1, 2, '2021-10-13', 3, 4, 51)

-- eid is not having fever, room is not approved, capacity is not enough (cannot join)
-- join_meeting(2, 9, '2021-10-17', 3, 4, 51)

-- eid is not having fever, room is approved (cannot join)
-- join_meeting(2, 3, '2021-10-14', 10, 11, 48)

-- eid is having fever (cannot join)
-- join_meeting(2, 9, '2021-10-14', 23, 24, 52)
CREATE OR REPLACE FUNCTION join_meeting
    (IN query_floor_num INT, IN query_room_num INT, IN query_date DATE, IN query_start_hour INT, IN query_end_hour INT, IN query_eid INT)
RETURNS VOID AS $$
DECLARE
    today_date DATE := NULL;
    time_diff INT := -1;
    booker_temp NUMERIC := -1;
    approval_eid INT := -1;
    room_cap INT := -1;
    curr_participants INT := -1;
BEGIN
    SELECT CURRENT_DATE INTO today_date;
    time_diff := query_end_hour - query_start_hour;
    IF time_diff >= 1 THEN
        SELECT temp INTO booker_temp
        FROM HealthDeclarations
        WHERE eid = query_eid
        AND date = today_date;

        IF booker_temp <= 37.5 THEN
            WHILE time_diff >= 1 LOOP
                SELECT approval_id INTO approval_eid
                FROM Sessions
                WHERE floor_num = query_floor_num
                AND room_num = query_room_num
                AND date = query_date
                AND time = query_start_hour;

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
                    AND time = query_start_hour;

                    IF room_cap - curr_participants - 1 > 0 THEN -- -1 because the booker is also considered a participant
                        INSERT INTO Joins (eid, time, date, floor_num, room_num) VALUES (query_eid, query_start_hour, query_date, query_floor_num, query_room_num);
                    END IF;
                END IF;
                query_start_hour := query_start_hour + 1;
                time_diff := query_end_hour - query_start_hour;
            END LOOP;
        END IF;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- ALL TESTED EXCEPT FOR >1H
-- testcases to test:
-- eid is not in meeting (don't do anything)
-- leave_meeting(2, 9, '2021-10-20', 0, 1, 1)

-- eid is in meeting, meeting is not approved (can leave)
-- leave_meeting(1, 4, '2021-10-13', 0, 1, 9)

-- eid is in meeting, meeting is approved (cannot leave)
-- leave_meeting(2, 3, '2021-10-14', 10, 11, 51)
CREATE OR REPLACE FUNCTION leave_meeting
    (IN query_floor_num INT, IN query_room_num INT, IN query_date DATE, IN query_start_hour INT, IN query_end_hour INT, IN query_eid INT)
RETURNS VOID AS $$
DECLARE
    time_diff INT := -1;
    is_in_meeting INT := -1;
    approval_eid INT := -1;
BEGIN
    time_diff := query_end_hour - query_start_hour;
    WHILE time_diff >= 1 LOOP
        SELECT COUNT(*) INTO is_in_meeting
        FROM Joins
        WHERE eid = query_eid
        AND floor_num = query_floor_num
        AND room_num = query_room_num
        AND date = query_date
        AND time = query_start_hour;

        IF is_in_meeting > 0 THEN
            SELECT approval_id INTO approval_eid
            FROM Sessions
            WHERE floor_num = query_floor_num
            AND room_num = query_room_num
            AND date = query_date
            AND time = query_start_hour;

            IF approval_eid IS NULL THEN
                DELETE FROM Joins
                WHERE eid = query_eid
                AND floor_num = query_floor_num
                AND room_num = query_room_num
                AND date = query_date
                AND time = query_start_hour;
            END IF;
        END IF;
        query_start_hour := query_start_hour + 1;
        time_diff := query_end_hour - query_start_hour;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- ALL TESTED EXCEPT >1H
-- testcases to test:
-- eid is manager, room belongs to same department as manager (can approve)
-- approve_meeting(2, 3, '2021-10-14', 10, 11, 93)

-- eid is manager, room belongs to different department as manager (cannot approve)
-- approve_meeting(2, 5, '2021-10-14', 22, 23, 86)

-- eid is not a manager (cannot approve)
-- approve_meeting(2, 5, '2021-10-14', 22, 23, 1)
CREATE OR REPLACE FUNCTION approve_meeting
    (IN query_floor_num INT, IN query_room_num INT, IN query_date DATE, IN query_start_hour INT, IN query_end_hour INT, IN query_eid INT)
RETURNS VOID AS $$
DECLARE
    time_diff INT := -1;
    manager_eid INT := -1;
    manager_did INT := -1;
    room_did INT := -1;
BEGIN
    time_diff := query_end_hour - query_start_hour;
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
                AND time = query_start_hour;
            END IF;
        END IF;
        query_start_hour := query_start_hour + 1;
        time_diff := query_end_hour - query_start_hour;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
