-- search_room
-- - returns all rooms available from [start_hour, end_hour)
-- - sort in ascending order of capacity
-- available = does not appear in Sessions (booker_id not null)

-- testcases to test:
-- room is available
-- room is unavailable
CREATE OR REPLACE FUNCTION search_room
    (IN query_cap INT, IN query_date DATE, IN query_start_hour INT, IN query_end_hour INT,
    OUT out_floor_num INT, OUT out_room_num INT, OUT out_did INT, OUT out_cap INT)
RETURNS RECORD AS $$
BEGIN
    WITH UnavailableRooms AS (
        SELECT floor_num, room_num
        FROM Sessions
        WHERE date = query_date
        AND time BETWEEN query_start_hour AND query_end_hour - 1
    ), AvailableRooms AS (
        SELECT floor_num, room_num, did
        FROM MeetingRooms m, UnavailableRooms u
        WHERE m.floor_num <> u.floor_num
        AND m.room_num <> u.room_num
    )
    
    SELECT floor_num, room_num, did
    INTO out_floor_num, out_room_num, out_did
    FROM AvailableRooms;

    SELECT new_cap
    INTO out_cap
    FROM Updates u, AvailableRooms a
    WHERE u.floor_num = a.floor_num
    AND u.room_num = a.room_num
    ORDER BY new_cap;
END;
$$ LANGUAGE plpgsql

-- book_room
-- - A senior employee or a manager books a room by specifying the room and the session.
-- - If the room is not available for the given session, no booking can be done.
-- - If the employee is having a fever, they cannot book any room.
-- assumptions made:
-- query_eid can only book a room on query_date, from [query_start_hour, query_end_hour) only if:
-- 1. query_eid is a booker
-- 2. query_eid is not having a fever
-- 3. a room is available on query_date, from [query_start_hour, query_end_hour)

-- testcases to test:
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
    time_diff INT := -1;
    booker_eid INT := -1;
    booker_temp NUMERIC := -1;
    is_room_avail INT := -1;
BEGIN
    time_diff := query_end_hour - query_start_hour;
    IF time_diff >= 1 THEN
        SELECT eid INTO booker_eid
        FROM Bookers
        WHERE eid = query_eid;

        IF booker_eid <> -1 THEN -- is a booker
            SELECT temp INTO booker_temp
            FROM HealthDeclarations
            WHERE eid = booker_eid;

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
$$ LANGUAGE plpgsql

-- unbook_room
-- - eid must be the employee who did the booking
-- - if booking is approved, remove approval
-- - if there are employees already joining, remove them
-- assumptions made:
-- this function is to unbook a meeting room on query_date, from [query_start_hour, query_end_hour) and on query_date only made by query_eid
-- for example if the query is [10am, 12pm),
-- and if query_eid only made a booking from [10am, 11am) OR query_eid made a booking from [10am, 1pm), this room will not be unbooked
-- but if query_eid made a booking from [10am, 12pm), this room will be unbooked

-- testcases to test:
-- eid is valid, booking is not approved, no employees joining (can unbook)
-- eid is valid, booking is not approved, employees joining (can unbook, remove employees)
-- eid is valid, booking is approved, no employees joining (can unbook, remove approval)
-- eid is valid, booking is approved, employees joining (can unbook, remove approval and employees)
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

            IF approval_eid <> -1 AND approval_eid IS NOT NULL THEN
                -- remove approval
                DELETE FROM Sessions
                WHERE booker_id = booker_eid
                AND floor_num = query_floor_num
                AND room_num = query_room_num
                AND date = query_date
                AND time = temp_query_start_hour;
            END IF;

            -- remove participants
            DELETE FROM Joins
            WHERE floor_num = query_floor_num
            AND room_num = query_room_num
            AND date = query_date
            AND time = temp_query_start_hour;

            temp_query_start_hour := temp_query_start_hour + 1;
            time_diff := query_end_hour - temp_query_start_hour;
        END LOOP;
    END IF;
END;
$$ LANGUAGE plpgsql

-- join_meeting
-- - if employee is allowed to join
-- - employee cannot join an approved meeting (meaning only booked meeting)

-- testcases to test:
-- eid is not having fever, room is not approved, capacity is enough (can join)
-- eid is not having fever, room is not approved, capacity is not enough (cannot join)
-- eid is not having fever, room is approved (cannot join)
-- eid is having fever, room is not approved (cannot join)
-- eid is having fever, room is approved (cannot join)
CREATE OR REPLACE FUNCTION join_meeting
    (IN query_floor_num INT, IN query_room_num INT, IN query_date DATE, IN query_start_hour INT, IN query_end_hour INT, IN query_eid INT)
RETURNS VOID AS $$
DECLARE
    time_diff INT := -1;
    booker_temp NUMERIC := -1;
    approval_eid INT := -1;
    room_cap INT := -1;
    curr_participants INT := -1;
BEGIN
    time_diff := query_end_hour - query_start_hour;
    IF time_diff >= 1 THEN
        SELECT temp INTO booker_temp
        FROM HealthDeclarations
        WHERE eid = query_eid;

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
$$ LANGUAGE plpgsql

-- leave_meeting
-- - if employee is not in meeting, don't do anything
-- - employee is not allowed to leave an approved meeting (meaning only booked meeting)

-- testcases to test:
-- eid is not in meeting (don't do anything)
-- eid is in meeting, meeting is not approved (can leave)
-- eid is in meeting, meeting is approved (cannot leave)
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
$$ LANGUAGE plpgsql

-- approve_meeting
-- - eid must be a manager
-- - check if approval is allowed

-- eid is manager, room belongs to same department as manager (can approve)
-- eid is manager, room belongs to different department as manager (cannot approve)
-- eid is not a manager (cannot approve)
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
$$ LANGUAGE plpgsql
