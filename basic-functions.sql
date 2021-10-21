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
BEGIN
	SELECT did INTO d_id FROM Employees WHERE eid = e_id;
	SELECT did INTO room_did FROM MeetingRooms WHERE floor_num = floornum AND room_num = roomnum;
	IF d_id = room_did THEN 
		IF (today_date, floornum, roomnum) IN (SELECT date, floor_num, room_num FROM Updates) 
			THEN UPDATE Updates
				 SET new_cap = room_cap, eid = e_id
				 WHERE date = today_date AND floor_num = floornum AND room_num = roomnum; 
		ELSE INSERT INTO Updates (date, new_cap, floor_num, room_num, eid) VALUES (today_date, room_cap, floornum, roomnum, e_id);
		END IF;
	ELSE RAISE EXCEPTION USING
		errcode='NODID';
	END IF;
	
EXCEPTION 
	WHEN sqlstate 'NODID' THEN RAISE EXCEPTION 'Only employees from the same department as the room can change the capacity!';
	
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