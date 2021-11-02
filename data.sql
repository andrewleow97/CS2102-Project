-- DATA SQL to load data into application database

TRUNCATE Departments, Employees, Junior, Booker, Senior, Manager,
         MeetingRooms, Sessions, Joins, HealthDeclaration, Updates;

INSERT INTO Departments (did, dname) VALUES
    (1, 'Legal'),
    (2, 'Human Resources'),
    (3, 'Engineering'),
    (4, 'Support'),
    (5, 'Business Development'),
    (6, 'Research and Development'),
    (7, 'Marketing'),
    (8, 'Accounting'),
    (9, 'Services'),
    (10, 'Software')
;

INSERT INTO Employees (eid, did, ename, email, mobile_phone, home_phone, office_phone, resigned_date) VALUES
--Junior
  (1, 8, 'Yotbx', 'Yotbx1@gmail.com', '90765512', null, null, null),
  (2, 6, 'Hjoda', 'Hjoda2@gmail.com', '93143064', '60613268', null, null),
  (3, 6, 'Ncerf', 'Ncerf3@gmail.com', '91291975', '63494095', '63769002', null),
  (4, 4, 'Rwzer', 'Rwzer4@gmail.com', '93912097', null, '66965520', null),
  (5, 3, 'Aqcug', 'Aqcug5@gmail.com', '95193842', '60520104', '64504897', null),
  (6, 5, 'Mlmzq', 'Mlmzq6@gmail.com', '90617332', null, '69046112', null),
  (7, 8, 'Hvxer', 'Hvxer7@gmail.com', '96189252', '66301886', '68678425', null),
  (8, 7, 'Njgst', 'Njgst8@gmail.com', '95075745', null, '67297031', null),
  (9, 3, 'Fjsyf', 'Fjsyf9@gmail.com', '93426370', '61185057', '64253874', null),
  (10, 5, 'Znuck', 'Znuck10@gmail.com', '94269305', '67860182', null, null),
--Booker (Senior)
  (11, 2, 'Baoen', 'Baoen11@gmail.com', '91328178', '67870273', '63576041', null),
  (12, 2, 'Tmukf', 'Tmukf12@gmail.com', '93153994', '60390470', '63798048', null),
  (13, 9, 'Oxctj', 'Oxctj13@gmail.com', '93350674', '68227059', '61548588', null),
  (14, 10, 'Catty', 'Catty14@gmail.com', '94665698', null, '63282043', null),
  (15, 3, 'Fishy', 'Fishy15@gmail.com', '90644905', '60070921', '67966699', null),
  (16, 2, 'Vhgjz', 'Vhgjz16@gmail.com', '96663886', '62632001', null, null),
  (17, 1, 'Jpcus', 'Jpcus17@gmail.com', '93267091', '64180950', '62089162', null),
  (18, 3, 'Xwfii', 'Xwfii18@gmail.com', '94977484', null, '65611340', null),
  (19, 10, 'Ifode', 'Ifode19@gmail.com', '94335409', '64001061', '66525566', null),
  (20, 9, 'Lzgee', 'Lzgee20@gmail.com', '97474618', '69551866', '61848588', null),
--Booker (Manager)
  (21, 3, 'Dgvyn', 'Dgvyn21@gmail.com', '93464073', null, '63509017', null),
  (22, 8, 'Hcafj', 'Hcafj22@gmail.com', '91044192', '64882597', '60888192', null),
  (23, 7, 'Eodkm', 'Eodkm23@gmail.com', '93373824', '68332134', '62797866', null),
  (24, 2, 'Crxyz', 'Crxyz24@gmail.com', '94640558', null, '64659208', null),
  (25, 9, 'Omkel', 'Omkel25@gmail.com', '97946643', '64043881', '67408265', null),
  (26, 9, 'Mjbwm', 'Mjbwm26@gmail.com', '96321443', null, '66228063', null),
  (27, 8, 'Erftt', 'Erftt27@gmail.com', '90038444', '63158929', '68530216', null),
  (28, 7, 'Baqvi', 'Baqvi28@gmail.com', '90298132', '60102449', '65361601', null),
  (29, 4, 'Tjfvc', 'Tjfvc29@gmail.com', '90657759', null, '69034164', null),
  (30, 6, 'Wscon', 'Wscon30@gmail.com', '94629056', '63617133', '67025443', null)
;

INSERT INTO Junior (eid) VALUES 
  (1), (2), (3), (4), (5), (6), (7), (8), (9), (10)
;

INSERT INTO Booker (eid) VALUES 
  (11), (12), (13), (14), (15), (16), (17), (18), (19), (20),
  (21), (22), (23), (24), (25), (26), (27), (28), (29), (30)
;

INSERT INTO Senior (eid) VALUES
  (11), (12), (13), (14), (15), (16), (17), (18), (19), (20)
;

INSERT INTO Manager (eid) VALUES
  (21), (22), (23), (24), (25), (26), (27), (28), (29), (30)
;

INSERT INTO MeetingRooms (floor, room, rname, did) VALUES 
  (1, 1, 'Room 1-1', 2),
  (1, 2, 'Room 1-2', 3),
  (1, 6, 'Room 1-1', 4),
  (2, 1, 'Room 2-1', 3),
  (2, 2, 'Room 2-2', 7),
  (2, 7, 'Room 2-7', 9),
  (3, 2, 'Room 3-2', 6),
  (3, 3, 'Room 3-3', 8),
  (4, 5, 'Room 4-5', 6),
  (5, 3, 'Room 5-3', 9)
;

INSERT INTO Updates (date, new_capacity, floor, room, eid) VALUES
  (CURRENT_DATE, 10, 1, 1, 24),
  (CURRENT_DATE, 10, 1, 2, 21), 
  (CURRENT_DATE, 10, 1, 6, 29), 
  (CURRENT_DATE, 20, 2, 1, 21),
  (CURRENT_DATE, 20, 2, 2, 23),
  (CURRENT_DATE, 20, 2, 7, 25),
  (CURRENT_DATE, 30, 3, 2, 30), 
  (CURRENT_DATE, 30, 3, 3, 22),
  (CURRENT_DATE, 30, 4, 5, 30), 
  (CURRENT_DATE, 40, 5, 3, 25)
;

INSERT INTO HealthDeclaration (eid, date, temperature, fever) VALUES 
  (1, CURRENT_DATE, 36.7, 'false'),
  (2, CURRENT_DATE, 37.4, 'false'),
  (3, CURRENT_DATE, 36.7, 'false'),
  (4, CURRENT_DATE, 36.5, 'false'),
  (5, CURRENT_DATE, 38.0, 'true'),
  (6, CURRENT_DATE, 36.2, 'false'),
  (7, CURRENT_DATE, 36.2, 'false'),
  (8, CURRENT_DATE, 36.0, 'false'),
  (9, CURRENT_DATE, 37.5, 'true'),
  (10, CURRENT_DATE, 36.7, 'false'),
  (11, CURRENT_DATE, 36.7, 'false'),
  (12, CURRENT_DATE, 37.4, 'false'),
  (13, CURRENT_DATE, 36.7, 'false'),
  (14, CURRENT_DATE, 36.5, 'false'),
  (15, CURRENT_DATE, 38.0, 'true'),
  (16, CURRENT_DATE, 36.2, 'false'),
  (17, CURRENT_DATE, 36.2, 'false'),
  (18, CURRENT_DATE, 36.0, 'false'),
  (19, CURRENT_DATE, 37.5, 'true'),
  (20, CURRENT_DATE, 36.7, 'false'),
  (21, CURRENT_DATE, 36.7, 'false'),
  (22, CURRENT_DATE, 37.4, 'false'),
  (23, CURRENT_DATE, 36.7, 'false'),
  (24, CURRENT_DATE, 36.5, 'false'),
  (25, CURRENT_DATE, 38.0, 'true'),
  (26, CURRENT_DATE, 36.2, 'false'),
  (27, CURRENT_DATE, 36.2, 'false'),
  (28, CURRENT_DATE, 36.0, 'false'),
  (29, CURRENT_DATE, 37.5, 'true'),
  (30, CURRENT_DATE, 36.7, 'false'),

  -- HealthDeclaration for Bookers
  (11, CURRENT_DATE + 1, 36.5, 'false'),
  (21, CURRENT_DATE + 2, 36.5, 'false'),
  (15, CURRENT_DATE + 3, 36.5, 'false'),
  (23, CURRENT_DATE + 3, 36.5, 'false'),
  (24, CURRENT_DATE + 4, 36.5, 'false'),
  (12, CURRENT_DATE + 5, 36.5, 'false'),
  (23, CURRENT_DATE + 6, 36.5, 'false'),
  (18, CURRENT_DATE + 7, 36.5, 'false'),
  (11, CURRENT_DATE + 8, 36.5, 'false'),
  (15, CURRENT_DATE + 9, 36.5, 'false')
;

INSERT INTO Sessions (date, time, floor, room, booker_id, approver_id) VALUES 
  (CURRENT_DATE + 1, 18, 1, 1, 11, null),
  (CURRENT_DATE + 2, 13, 2, 1, 21, null),
  (CURRENT_DATE + 3, 16, 3, 2, 15, null),
  (CURRENT_DATE + 3, 19, 1, 1, 23, null),
  (CURRENT_DATE + 4, 17, 1, 6, 24, null),
  (CURRENT_DATE + 5, 8, 1, 1, 12, null),
  (CURRENT_DATE + 6, 9, 5, 3, 23, null),
  (CURRENT_DATE + 7, 14, 3, 3, 18, null),
  (CURRENT_DATE + 8, 11, 2, 2, 11, null),
  (CURRENT_DATE + 9, 10, 3, 3, 15, null)
;

-- Booker must join the session (enforced by trigger)
INSERT INTO Joins (eid, date, time, floor, room) VALUES 
  (6, CURRENT_DATE + 2, 13, 2, 1),
  (8, CURRENT_DATE + 2, 13, 2, 1),
  (19, CURRENT_DATE + 2, 13, 2, 1),
  (2, CURRENT_DATE + 3, 19, 1, 1),
  (30, CURRENT_DATE + 3, 19, 1, 1),
  (26, CURRENT_DATE + 3, 19, 1, 1),
  (24, CURRENT_DATE + 3, 19, 1, 1),
  (2, CURRENT_DATE + 6, 9, 5, 3),
  (3, CURRENT_DATE + 6, 9, 5, 3),
  (15, CURRENT_DATE + 6, 9, 5, 3),
  (26, CURRENT_DATE + 6, 9, 5, 3),
  (17, CURRENT_DATE + 6, 9, 5, 3),
  (11, CURRENT_DATE + 6, 9, 5, 3),
  (10, CURRENT_DATE + 6, 9, 5, 3),
  (27, CURRENT_DATE + 7, 14, 3, 3),
  (6, CURRENT_DATE + 7, 14, 3, 3)
;