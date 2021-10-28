-- ADMIN FUNCTIONS

/* Employees checked from start_date to 
end_date/res_date, whichever is earlier. */
CREATE OR REPLACE FUNCTION non_compliance
    (IN _start_date DATE, IN _end_date DATE)
RETURNS TABLE(eid INT, days_recorded BIGINT) AS $$
BEGIN
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
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION view_booking_report
    (IN _start_date DATE, IN _eid INT)
RETURNS TABLE(floor_num INT, room_num INT, date DATE, start_hour INT, is_approved BOOLEAN) AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT s.floor_num, s.room_num, s.date, s.time, s.approval_id IS NOT NULL AS is_approved
    FROM Sessions s
    WHERE s.booker_id = _eid AND s.date >= _start_date
    GROUP BY s.floor_num, s.room_num, s.date, s.time
    ORDER BY s.date, s.time ASC;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION view_future_meeting
    (IN _start_date DATE, IN _eid INT)
RETURNS TABLE(floor_num INT, room_num INT, date DATE, start_hour INT) AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT sj.floor_num, sj.room_num, sj.date, sj.time
    FROM (Sessions NATURAL JOIN Joins) AS sj
    WHERE sj.eid = _eid AND sj.date >= _start_date AND sj.approval_id IS NOT NULL
    GROUP BY sj.floor_num, sj.room_num, sj.date, sj.time
    ORDER BY sj.date, sj.time ASC;
END;
$$ LANGUAGE plpgsql;

-- eid refers to manager id
CREATE OR REPLACE FUNCTION view_manager_report
    (IN _start_date DATE, IN _eid INT)
RETURNS TABLE(floor_num INT, room_num INT, date DATE, start_hour INT, eid INT) AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT m.floor_num, m.room_num, m.date, m.time, m.eid
    FROM (Departments NATURAL JOIN Employees NATURAL JOIN Managers NATURAL JOIN MeetingRooms NATURAL JOIN Sessions) as m 
    WHERE m.eid =  _eid AND m.approval_id IS NULL AND m.date >= _start_date
    GROUP BY m.floor_num, m.room_num, m.date, m.time, m.eid
    ORDER BY m.date, m.time ASC;
END;
$$ LANGUAGE plpgsql;
