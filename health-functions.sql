--declare_health
CREATE OR REPLACE FUNCTION declare_health (IN id INT, IN date DATE, IN temperature NUMERIC) RETURNS VOID AS 
$$
BEGIN
	INSERT INTO HealthDeclarations (date, temp, eid) VALUES (date, temperature, id);
END
$$ 
	LANGUAGE plpgsql;

