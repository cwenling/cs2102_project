--add_department
CREATE OR REPLACE FUNCTION add_department (IN id INT, IN name TEXT) RETURNS VOID AS 
$$
BEGIN
	INSERT INTO Departments (did, dname) VALUES (id, name);
END
$$ 
	LANGUAGE plpgsql;


--remove_department
CREATE OR REPLACE FUNCTION remove_department (IN id INT) RETURNS VOID AS 
$$
BEGIN
	DELETE FROM Departments
	WHERE did = id;
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
END
$$ 
	LANGUAGE plpgsql;


--change_capacity
-- drawbacks: cannot update cap with same date and room num and floor num
CREATE OR REPLACE FUNCTION change_capacity 
	(IN floornum INT, IN roomnum INT, IN room_cap INT, IN today_date DATE, IN e_id INT) RETURNS VOID AS 
$$
DECLARE 
	d_id INT;
	room_did INT;
BEGIN
	SELECT did INTO d_id FROM Employees WHERE eid = e_id;
	SELECT did INTO room_did FROM MeetingRooms WHERE floor_num = floornum AND room_num = roomnum;
	IF d_id = room_did THEN INSERT INTO Updates (date, new_cap, floor_num, room_num, eid) VALUES (today_date, room_cap, floornum, roomnum, e_id);
	ELSE 
	END IF;
END
$$ 
	LANGUAGE plpgsql;


--add_employee (doesnt work)
/*
CREATE OR REPLACE FUNCTION add_employee 
	(IN name TEXT, IN home_con INT, IN mobile_con INT, IN office_con INT, IN type TEXT, IN d_id INT) RETURNS VOID AS 
$$
DECLARE 
	e_id INT;
	e_id_str TEXT;
	g_email TEXT;
BEGIN
	SELECT eid, COUNT(*) INTO e_id FROM Employees GROUP BY eid;	
	SELECT CAST(e_id AS TEXT) INTO e_id_str;
	SELECT CONCAT(e_id_str, '_', name, '@company.com');
	
	INSERT INTO Employees VALUES (e_id, name, home_con, mobile_con, office_con, g_email, null, d_id);
	
	IF type = 'junior' THEN INSERT INTO Juniors VALUES (e_id);
	ELSE INSERT INTO Bookers VALUES (e_id);
	END IF;
	
	IF type = 'senior' THEN INSERT INTO Seniors VALUES (e_id);
	ELSIF type = 'manaager' THEN INSERT INTO Managers VALUES (e_id);
	END IF;
END
$$ 
	LANGUAGE plpgsql;
*/

--remove_employee
CREATE OR REPLACE FUNCTION remove_employee 
	(IN e_id INT, IN date DATE) RETURNS VOID AS 
$$
BEGIN
	UPDATE Employees SET res_date = date WHERE eid = e_id;
END
$$ 
	LANGUAGE plpgsql;