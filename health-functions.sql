--declare_health
CREATE OR REPLACE FUNCTION declare_health (IN id INT, IN date DATE, IN temperature NUMERIC) RETURNS VOID AS 
$$
BEGIN
	INSERT INTO HealthDeclarations (date, temp, eid) VALUES (date, temperature, id);
END
$$ 
	LANGUAGE plpgsql;

--contact_tracing
----KIV: This employee cannot book a room until they are no longer having fever.
CREATE OR REPLACE FUNCTION contact_tracing (IN id INT) RETURNS TABLE(eid INT) AS 
$$
DECLARE
    declared_date DATE;
    declared_temp NUMERIC;
BEGIN
    SELECT max(date) INTO declared_date FROM HealthDeclarations WHERE eid = id;
    SELECT temp into declared_temp FROM HealthDeclarations WHERE eid = id AND date = date;
    IF declared_temp > 37.5 THEN
        DELETE FROM Joins WHERE date >= declared_date AND eid = id;
        DELETE FROM Sessions WHERE date >= declared_date AND booker_id = id;

        CREATE VIEW close_contacts AS
            SELECT j2.eid
            FROM Joins j1, Joins j2, Sessions s
            WHERE j1.eid = id
            AND s.approval_id IS NOT NULL
            AND s.date >= declared_date - 3
            AND s.date <= declared_date
            AND j1.time = s.time
            AND j1.date = s.date
            AND j1.floor_num = s.floor_num
            AND j1.room_num = s.room_num
            AND j2.time = s.time
            AND j2.date = s.date
            AND j2.floor_num = s.floor_num
            AND j2.room_num = s.room_num;
        DELETE FROM Joins WHERE eid IN (close_contacts) AND date >= declared_date AND date <= declared_date + 7;
        RETURN QUERY SELECT * FROM close_contacts;
    END IF;
END
$$ 
	LANGUAGE plpgsql;
