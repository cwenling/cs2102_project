/* Employees resigned between start_date and end_date will
be checked from start_date to end_date currently. Should we stop at their resignation date? */
CREATE OR REPLACE FUNCTION non_compliance
    (IN _start_date DATE, IN _end_date DATE)
RETURNS TABLE(eid INT, days_recorded BIGINT) AS $$
BEGIN
    RETURN QUERY
    SELECT hd.eid, COUNT(DISTINCT hd.date)
    FROM HealthDeclarations hd 
    WHERE date BETWEEN _start_date AND _end_date
    GROUP BY hd.eid
    HAVING COUNT(DISTINCT hd.date) < end_date - _start_date;
END;
$$ LANGUAGE plpgsql;

/* What value do we want for is_approved? */
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
