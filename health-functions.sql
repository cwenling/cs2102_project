CREATE TRIGGER contact_trace_if_fever
AFTER INSERT ON HealthDeclarations
FOR EACH ROW WHEN (temperature > 37.5)
EXECUTE FUNCTION contact_tracing();

--declare_health
CREATE OR REPLACE FUNCTION declare_health (IN input_id INT, IN input_date DATE, IN input_temp NUMERIC) RETURNS VOID AS 
$$
BEGIN
	INSERT INTO HealthDeclarations (date, temp, eid) VALUES (date, temperature, id);
    RETURN VOID;
END
$$ 
	LANGUAGE plpgsql;

--contact_tracing, returns table of close contacts to employee id.
CREATE OR REPLACE FUNCTION contact_tracing (IN traced_id INT) RETURNS TABLE(eid INT) AS 
$$
DECLARE
    declared_date DATE;
    declared_temp NUMERIC;
    declared_time INTEGER;
BEGIN
    SELECT max(date) INTO declared_date FROM HealthDeclarations WHERE eid = traced_id;
    SELECT temp INTO declared_temp FROM HealthDeclarations WHERE eid = traced_id AND date = declared_date;
    SELECT EXTRACT(HOUR FROM localtime) INTO declared_time FROM NOW();
    IF declared_temp > 37.5 THEN
        CREATE VIEW close_contacts ON COMMIT DROP AS
            (SELECT j2.eid
            FROM Joins j1, Joins j2, Sessions s
            WHERE j1.eid = traced_id
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
            WHERE j1.eid = id
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

        DELETE FROM Joins WHERE ((date > declared_date) OR (date = declared_date AND time > declared_time))  AND eid = id;
        DELETE FROM Sessions WHERE ((date > declared_date) OR (date = declared_date AND time > declared_time)) AND booker_id = id;

        DELETE FROM Joins WHERE eid IN (close_contacts) AND ((date > declared_date) OR (date = declared_date AND time > declared_time)) AND date <= declared_date + 7;
        UPDATE Employees SET end_date = declared_date + 7;
        RETURN QUERY SELECT * FROM close_contacts;
    END IF;
END
$$ 
	LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION contact_trace (IN id INT) RETURNS TRIGGER AS 
$$
BEGIN
    SELECT * FROM contact_tracing(NEW.eid);
    RETURN NULL;
END
$$ 
	LANGUAGE plpgsql;