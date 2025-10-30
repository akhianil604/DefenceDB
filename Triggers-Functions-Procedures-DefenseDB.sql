USE defense_db;
DELIMITER $$
			# FUNCTIONS
# F1. Compute total cost for a product & quantity
CREATE FUNCTION calc_total_cost(p_item_id VARCHAR(7), p_qty INT)
	RETURNS DECIMAL(20,2)
	DETERMINISTIC
	BEGIN
		DECLARE v_unit DECIMAL(20,2);
		IF p_qty IS NULL OR p_qty <= 0 THEN
			SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Quantity must be positive.';
		END IF;
        
		SELECT Unit_Cost INTO v_unit
		FROM PRODUCT
		WHERE Item_ID = p_item_id;

		IF v_unit IS NULL THEN
			SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Unknown Item_ID.';
		END IF;
	RETURN v_unit * p_qty;
END$$

# F2. Remaining budget for a department
CREATE FUNCTION dept_budget_left(p_dept_id VARCHAR(6))
	RETURNS DECIMAL(20,2)
	DETERMINISTIC
	BEGIN
		DECLARE v_left DECIMAL(20,2);
		SELECT Current_Budget INTO v_left
		FROM DEPARTMENT
		WHERE Dept_ID = p_dept_id;

		IF v_left IS NULL THEN
		SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Unknown Dept_ID.';
		END IF;
	RETURN v_left;
END$$

# F3. Can fulfill stock?
CREATE FUNCTION can_fulfill_stock(p_item_id VARCHAR(7), p_qty INT)
RETURNS INTEGER
DETERMINISTIC
BEGIN
  DECLARE v_stock INT;
  IF p_qty IS NULL OR p_qty <= 0 THEN
    RETURN 0;
  END IF;

  SELECT Stock_Available INTO v_stock
  FROM PRODUCT WHERE Item_ID = p_item_id;

  IF v_stock IS NULL THEN
    RETURN 0;
  END IF;

  RETURN (v_stock >= p_qty);
END$$

# F4. Normalize product category to whitelist
CREATE FUNCTION normalize_category(p_cat VARCHAR(50))
RETURNS VARCHAR(50)
DETERMINISTIC
BEGIN
  IF p_cat IN (
    'Tanks','Armored Trucks','Fighter Jets','Submarines','Drones','Transport Aircraft',
    'Rifles','Missiles','Artillery System','Air-defence systems',
    'Radios','Satellite Phones','Secure Routers','Command Servers','Radar installations',
    'Firewalls','Threat monitoring platforms','Data centers',
    'Helmets','Defence suits','Uniform',
    'First-aid kits','Medical drones','Surgical instruments',
    'Others'
  ) THEN
    RETURN p_cat;
  END IF;

  IF p_cat = 'Threat Intelligence Platform' THEN RETURN 'Threat monitoring platforms'; END IF;
  IF p_cat = 'Boots' THEN RETURN 'Uniform'; END IF;
  IF p_cat IN ('Field Hospitals','Miscellaneous') THEN RETURN 'Others'; END IF;

  RETURN 'Others';
END$$

# F5. Compute request total from its current fields
CREATE FUNCTION request_total_cost(p_request_id VARCHAR(10))
RETURNS DECIMAL(20,2)
DETERMINISTIC
BEGIN
  DECLARE v_item VARCHAR(7);
  DECLARE v_qty INT;
  DECLARE v_sum DECIMAL(20,2);

  SELECT Item_ID, Quantity INTO v_item, v_qty
  FROM PROCUREMENT_REQUEST WHERE Request_ID = p_request_id;

  IF v_item IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Unknown Request_ID.';
  END IF;

  SET v_sum = calc_total_cost(v_item, v_qty);
  RETURN v_sum;
END$$

# F6 Department Efficiency %
CREATE FUNCTION get_department_efficiency(p_dept_id VARCHAR(6))
RETURNS DECIMAL(5,2)
DETERMINISTIC
BEGIN
    DECLARE v_alloc DECIMAL(20,8);
    DECLARE v_current DECIMAL(20,8);
    DECLARE v_eff DECIMAL(5,2);

    SELECT Budget_Allocated, Current_Budget
    INTO v_alloc, v_current
    FROM DEPARTMENT
    WHERE Dept_ID = p_dept_id;

    IF v_alloc IS NULL OR v_alloc = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Invalid Department or Allocation.';
    END IF;

    SET v_eff = (v_current / v_alloc) * 100;
    RETURN ROUND(v_eff, 2);
END$$


# F7 Average vendor contract duration (in days)
CREATE FUNCTION avg_vendor_contract_duration()
RETURNS DECIMAL(10,2)
DETERMINISTIC
BEGIN
    DECLARE v_avg DECIMAL(10,2);
    SELECT AVG(DATEDIFF(Contract_Expiry_Date, CURDATE()))
    INTO v_avg
    FROM VENDOR
    WHERE Contract_Expiry_Date IS NOT NULL;
    RETURN IFNULL(v_avg, 0);
END$$


# F8 Pending request count for department
CREATE FUNCTION get_pending_requests_count(p_dept_id VARCHAR(6))
RETURNS INT
DETERMINISTIC
BEGIN
    DECLARE v_count INT;
    SELECT COUNT(*) INTO v_count
    FROM PROCUREMENT_REQUEST
    WHERE Dept_ID = p_dept_id AND Status = 'Pending';
    RETURN v_count;
END$$


						# PROCEDURES
# P1. Create a new request (validations + compute total)
CREATE PROCEDURE create_procurement_request(
  IN p_request_id VARCHAR(10),
  IN p_dept_id    VARCHAR(6),
  IN p_item_id    VARCHAR(7),
  IN p_vendor_id  VARCHAR(6),
  IN p_qty        INT
)
BEGIN
  DECLARE v_cost DECIMAL(20,2);
  DECLARE v_vendor_of_item VARCHAR(6);
  DECLARE v_blacklisted BOOLEAN;

  IF EXISTS(SELECT 1 FROM PROCUREMENT_REQUEST WHERE Request_ID = p_request_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Request_ID already exists.';
  END IF;

  IF p_qty IS NULL OR p_qty <= 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Quantity must be positive.';
  END IF;

  # Validate foreign keys
  IF NOT EXISTS(SELECT 1 FROM DEPARTMENT WHERE Dept_ID = p_dept_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Unknown Dept_ID.';
  END IF;

  IF NOT EXISTS(SELECT 1 FROM PRODUCT WHERE Item_ID = p_item_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Unknown Item_ID.';
  END IF;

  IF NOT EXISTS(SELECT 1 FROM VENDOR WHERE Vendor_ID = p_vendor_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Unknown Vendor_ID.';
  END IF;

  SELECT Vendor_ID INTO v_vendor_of_item
  FROM PRODUCT WHERE Item_ID = p_item_id;

  IF v_vendor_of_item IS NULL OR v_vendor_of_item <> p_vendor_id THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Vendor does not supply the selected product.';
  END IF;

  # Check vendor status
  SELECT Blacklisted INTO v_blacklisted FROM VENDOR WHERE Vendor_ID = p_vendor_id;
  IF v_blacklisted THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Vendor is blacklisted.';
  END IF;

  # Compute total
  SET v_cost = calc_total_cost(p_item_id, p_qty);

  INSERT INTO PROCUREMENT_REQUEST
    (Request_ID, Dept_ID, Item_ID, Vendor_ID, Quantity, Total_Cost, Status, Request_Date)
  VALUES
    (p_request_id, p_dept_id, p_item_id, p_vendor_id, p_qty, v_cost, 'PENDING', NOW());
END$$

# P2. Approve a request (atomic workflow)
# STEPS:
# 1. Validates status
# 2. Checks dept budget & stock
# 3. Deducts stock, deducts dept budget
# 4. Writes to BUDGET_LOG
# 5. Stamps Approved_Date & Admin_ID
CREATE PROCEDURE approve_request(
  IN p_request_id VARCHAR(10),
  IN p_admin_id   VARCHAR(6)
)
BEGIN
  DECLARE v_status VARCHAR(20);
  DECLARE v_dept   VARCHAR(6);
  DECLARE v_item   VARCHAR(7);
  DECLARE v_vendor VARCHAR(6);
  DECLARE v_qty    INT;
  DECLARE v_total  DECIMAL(20,2);
  DECLARE v_budget DECIMAL(20,2);
  DECLARE v_stock  INT;

  # Lock rows we’ll touch to keep it consistent
  START TRANSACTION;

  # Validate admin
  IF NOT EXISTS(SELECT 1 FROM MINISTRY WHERE Admin_ID = p_admin_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Unknown Admin_ID.';
  END IF;

  # Load request (FOR UPDATE to serialize)
  SELECT Status, Dept_ID, Item_ID, Vendor_ID, Quantity, Total_Cost
    INTO v_status, v_dept, v_item, v_vendor, v_qty, v_total
  FROM PROCUREMENT_REQUEST
  WHERE Request_ID = p_request_id
  FOR UPDATE;

  IF v_status IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Unknown Request_ID.';
  END IF;

  IF v_status <> 'PENDING' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only PENDING requests can be approved.';
  END IF;

  # Budget check
  SELECT Current_Budget INTO v_budget
  FROM DEPARTMENT
  WHERE Dept_ID = v_dept
  FOR UPDATE;

  IF v_budget IS NULL OR v_budget < v_total THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient department budget.';
  END IF;

  # Stock check
  SELECT Stock_Available INTO v_stock
  FROM PRODUCT
  WHERE Item_ID = v_item
  FOR UPDATE;

  IF v_stock IS NULL OR v_stock < v_qty THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient stock.';
  END IF;

  # Deduct stock
  UPDATE PRODUCT
  SET Stock_Available = Stock_Available - v_qty
  WHERE Item_ID = v_item;

  # Deduct budget
  UPDATE DEPARTMENT
  SET Current_Budget = Current_Budget - v_total
  WHERE Dept_ID = v_dept;

  # Log budget movement
  INSERT INTO BUDGET_LOG (Log_ID, Dept_ID, Request_ID, Admin_ID, Amount, Action, Log_Timestamp)
  VALUES (CONCAT('BL', LPAD(FLOOR(RAND()*999999),6,'0')), v_dept, p_request_id, p_admin_id, v_total, 'DEDUCT', NOW());

  # Finalize request
  UPDATE PROCUREMENT_REQUEST
  SET Status = 'APPROVED',
      Approved_Date = NOW(),
      Admin_ID = p_admin_id,
      Total_Cost = v_total -- keep it explicit
  WHERE Request_ID = p_request_id;

  COMMIT;
END$$

# P3. Reject a request (Through the log, giving reasons)
CREATE PROCEDURE reject_request(
  IN p_request_id VARCHAR(10),
  IN p_admin_id   VARCHAR(6),
  IN p_reason     VARCHAR(255)
)
BEGIN
  DECLARE v_status VARCHAR(20);
  DECLARE v_dept   VARCHAR(6);

  START TRANSACTION;

  IF NOT EXISTS(SELECT 1 FROM MINISTRY WHERE Admin_ID = p_admin_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Unknown Admin_ID.';
  END IF;

  SELECT Status, Dept_ID INTO v_status, v_dept
  FROM PROCUREMENT_REQUEST
  WHERE Request_ID = p_request_id
  FOR UPDATE;

  IF v_status IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Unknown Request_ID.';
  END IF;

  IF v_status <> 'PENDING' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only PENDING requests can be rejected.';
  END IF;

  UPDATE PROCUREMENT_REQUEST
  SET Status = 'REJECTED',
      Approved_Date = NULL,
      Admin_ID = p_admin_id
  WHERE Request_ID = p_request_id;

  # Log as REFUND with 0 (acts like an audit note)
  INSERT INTO BUDGET_LOG (Log_ID, Dept_ID, Request_ID, Admin_ID, Amount, Action, Log_Timestamp)
  VALUES (CONCAT('BL', LPAD(FLOOR(RAND()*999999),6,'0')), v_dept, p_request_id, p_admin_id, 0, CONCAT('REJECT:', COALESCE(p_reason,'')), NOW());

  COMMIT;
END$$

# P4. Cancel an approved request (Restock & Refund)
CREATE PROCEDURE cancel_request(
  IN p_request_id VARCHAR(10),
  IN p_admin_id   VARCHAR(6),
  IN p_reason     VARCHAR(255)
)
BEGIN
  DECLARE v_status VARCHAR(20);
  DECLARE v_dept   VARCHAR(6);
  DECLARE v_item   VARCHAR(7);
  DECLARE v_qty    INT;
  DECLARE v_total  DECIMAL(20,2);

  START TRANSACTION;

  IF NOT EXISTS(SELECT 1 FROM MINISTRY WHERE Admin_ID = p_admin_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Unknown Admin_ID.';
  END IF;

  SELECT Status, Dept_ID, Item_ID, Quantity, Total_Cost
    INTO v_status, v_dept, v_item, v_qty, v_total
  FROM PROCUREMENT_REQUEST
  WHERE Request_ID = p_request_id
  FOR UPDATE;

  IF v_status IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Unknown Request_ID.';
  END IF;

  IF v_status <> 'APPROVED' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only APPROVED requests can be cancelled.';
  END IF;

  -- Restock
  UPDATE PRODUCT
  SET Stock_Available = Stock_Available + v_qty
  WHERE Item_ID = v_item;

  # Refund budget
  UPDATE DEPARTMENT
  SET Current_Budget = Current_Budget + v_total
  WHERE Dept_ID = v_dept;

  INSERT INTO BUDGET_LOG (Log_ID, Dept_ID, Request_ID, Admin_ID, Amount, Action, Log_Timestamp)
  VALUES (CONCAT('BL', LPAD(FLOOR(RAND()*999999),6,'0')), v_dept, p_request_id, p_admin_id, v_total, CONCAT('REFUND:', COALESCE(p_reason,'')), NOW());

  UPDATE PROCUREMENT_REQUEST
  SET Status = 'CANCELLED',
      Admin_ID = p_admin_id
  WHERE Request_ID = p_request_id;

  COMMIT;
END$$

# P5. Restock product
CREATE PROCEDURE restock_product(
  IN p_item_id VARCHAR(7),
  IN p_add_qty INT
)
BEGIN
  IF NOT EXISTS(SELECT 1 FROM PRODUCT WHERE Item_ID = p_item_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Unknown Item_ID.';
  END IF;

  IF p_add_qty IS NULL OR p_add_qty <= 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Restock quantity must be positive.';
  END IF;

  UPDATE PRODUCT
  SET Stock_Available = Stock_Available + p_add_qty
  WHERE Item_ID = p_item_id;
END$$

# P6. Blacklist a vendor and auto-reject pending requests for it
CREATE PROCEDURE blacklist_vendor(
  IN p_vendor_id VARCHAR(6),
  IN p_admin_id  VARCHAR(6),
  IN p_reason    VARCHAR(255)
)
BEGIN
  START TRANSACTION;

  IF NOT EXISTS(SELECT 1 FROM VENDOR WHERE Vendor_ID = p_vendor_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Unknown Vendor_ID.';
  END IF;

  UPDATE VENDOR SET Blacklisted = TRUE WHERE Vendor_ID = p_vendor_id;

  UPDATE PROCUREMENT_REQUEST
  SET Status = 'REJECTED', Admin_ID = p_admin_id
  WHERE Vendor_ID = p_vendor_id AND Status = 'PENDING';

  # One-liner BUDGET_LOG note
  INSERT INTO BUDGET_LOG (Log_ID, Dept_ID, Request_ID, Admin_ID, Amount, Action, Log_Timestamp)
  SELECT CONCAT('BL', LPAD(FLOOR(RAND()*999999),6,'0')),
         pr.Dept_ID, pr.Request_ID, p_admin_id, 0,
         CONCAT('VENDOR_BLACKLIST:', COALESCE(p_reason,'')),
         NOW()
  FROM PROCUREMENT_REQUEST pr
  WHERE pr.Vendor_ID = p_vendor_id AND pr.Status = 'REJECTED';

  COMMIT;
END$$

# P7. Log vendor contract renewal
CREATE PROCEDURE log_contract_renewal(
    IN p_vendor_id VARCHAR(6),
    IN p_new_expiry DATE,
    IN p_admin_id VARCHAR(6)
)
BEGIN
    DECLARE v_old DATE;

    SELECT Contract_Expiry_Date INTO v_old
    FROM VENDOR WHERE Vendor_ID = p_vendor_id;

    IF v_old IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Invalid Vendor_ID.';
    END IF;

    UPDATE VENDOR
    SET Contract_Expiry_Date = p_new_expiry
    WHERE Vendor_ID = p_vendor_id;

    INSERT INTO BUDGET_LOG (Log_ID, Category, Admin_ID, Amount, Timestamp)
    VALUES (
        CONCAT('BL', LPAD(FLOOR(RAND()*999999),6,'0')),
        CONCAT('Contract Renewed: ', DATE_FORMAT(v_old, '%Y-%m-%d'),
               ' → ', DATE_FORMAT(p_new_expiry, '%Y-%m-%d')),
        p_admin_id,
        0,
        NOW()
    );
END$$


# P8. Auto restock product when below threshold
CREATE PROCEDURE auto_restock_product(
    IN p_item_id VARCHAR(7),
    IN p_threshold INT,
    IN p_refill INT
)
BEGIN
    DECLARE v_stock INT;

    SELECT Stock_Available INTO v_stock FROM PRODUCT WHERE Item_ID = p_item_id;

    IF v_stock IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Unknown Product ID.';
    END IF;

    IF v_stock < p_threshold THEN
        UPDATE PRODUCT
        SET Stock_Available = Stock_Available + p_refill
        WHERE Item_ID = p_item_id;

        INSERT INTO BUDGET_LOG (Log_ID, Category, Request_ID, Amount, Timestamp)
        VALUES (
            CONCAT('BL', LPAD(FLOOR(RAND()*999999),6,'0')),
            CONCAT('Auto Restocked Product: ', p_item_id),
            NULL,
            0,
            NOW()
        );
    END IF;
END$$


						# TRIGGERS
# T1 - PRODUCT: Normalize category & clamp stock >= 0
DROP TRIGGER IF EXISTS trg_product_bi$$
CREATE TRIGGER trg_product_bi
BEFORE INSERT ON PRODUCT
FOR EACH ROW
BEGIN
  SET NEW.Category = normalize_category(NEW.Category);
  IF NEW.Stock_Available IS NULL OR NEW.Stock_Available < 0 THEN
    SET NEW.Stock_Available = GREATEST(COALESCE(NEW.Stock_Available,0), 0);
  END IF;
END$$

DROP TRIGGER IF EXISTS trg_product_bu$$
CREATE TRIGGER trg_product_bu
BEFORE UPDATE ON PRODUCT
FOR EACH ROW
BEGIN
  SET NEW.Category = normalize_category(NEW.Category);
  IF NEW.Stock_Available < 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Stock cannot be negative.';
  END IF;
END$$

# T2 - MINISTRY & VENDOR -  Basic Email Normalization to lowercase
DROP TRIGGER IF EXISTS trg_ministry_bi$$
CREATE TRIGGER trg_ministry_bi
BEFORE INSERT ON MINISTRY
FOR EACH ROW
BEGIN
  IF NEW.Email IS NOT NULL THEN
    SET NEW.Email = LOWER(NEW.Email);
  END IF;
END$$

DROP TRIGGER IF EXISTS trg_ministry_bu$$
CREATE TRIGGER trg_ministry_bu
BEFORE UPDATE ON MINISTRY
FOR EACH ROW
BEGIN
  IF NEW.Email IS NOT NULL THEN
    SET NEW.Email = LOWER(NEW.Email);
  END IF;
END$$

DROP TRIGGER IF EXISTS trg_vendor_bi$$
CREATE TRIGGER trg_vendor_bi
BEFORE INSERT ON VENDOR
FOR EACH ROW
BEGIN
  IF NEW.Email IS NOT NULL THEN
    SET NEW.Email = LOWER(NEW.Email);
  END IF;
END$$

DROP TRIGGER IF EXISTS trg_vendor_bu$$
CREATE TRIGGER trg_vendor_bu
BEFORE UPDATE ON VENDOR
FOR EACH ROW
BEGIN
  IF NEW.Email IS NOT NULL THEN
    SET NEW.Email = LOWER(NEW.Email);
  END IF;
END$$

# T3 - PROCUREMENT_REQUEST: Auto-calculates Total_Cost & Block edits after approval
DROP TRIGGER IF EXISTS trg_request_bi$$
CREATE TRIGGER trg_request_bi
BEFORE INSERT ON PROCUREMENT_REQUEST
FOR EACH ROW
BEGIN
  IF NEW.Quantity IS NULL OR NEW.Quantity <= 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Quantity must be positive.';
  END IF;

  # Validate Vendor supplies Item
  IF NOT EXISTS (
      SELECT 1 FROM PRODUCT p
      WHERE p.Item_ID = NEW.Item_ID AND p.Vendor_ID = NEW.Vendor_ID
  ) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Vendor does not supply the selected product.';
  END IF;

  # Compute total
  SET NEW.Total_Cost = calc_total_cost(NEW.Item_ID, NEW.Quantity);

  # Default status if missing
  IF NEW.Status IS NULL THEN
    SET NEW.Status = 'PENDING';
  END IF;
END$$

DROP TRIGGER IF EXISTS trg_request_bu$$
CREATE TRIGGER trg_request_bu
BEFORE UPDATE ON PROCUREMENT_REQUEST
FOR EACH ROW
BEGIN
  # Once approved/rejected/cancelled, lock identifiers & qty
  IF OLD.Status IN ('APPROVED','REJECTED','CANCELLED') THEN
    IF (NEW.Dept_ID <> OLD.Dept_ID) OR (NEW.Item_ID <> OLD.Item_ID) OR
       (NEW.Vendor_ID <> OLD.Vendor_ID) OR (NEW.Quantity <> OLD.Quantity) THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot change identifiers/quantity after finalization.';
    END IF;
  END IF;

  # Recompute total cost if qty or item changed (still pending)
  IF NEW.Status = 'PENDING' AND (NEW.Item_ID <> OLD.Item_ID OR NEW.Quantity <> OLD.Quantity) THEN
    SET NEW.Total_Cost = calc_total_cost(NEW.Item_ID, NEW.Quantity);
  END IF;
END$$

# T4 - BUDGET_LOG: Basic guard (No negative Amount)
DROP TRIGGER IF EXISTS trg_budgetlog_bi$$
CREATE TRIGGER trg_budgetlog_bi
BEFORE INSERT ON BUDGET_LOG
FOR EACH ROW
BEGIN
  IF NEW.Amount IS NULL OR NEW.Amount < 0 THEN
    SET NEW.Amount = 0;
  END IF;
  IF NEW.Timestamp IS NULL THEN
    SET NEW.Timestamp = NOW();
  END IF;
END$$

# T5 After procurement request approval
CREATE TRIGGER trg_after_request_approval
AFTER UPDATE ON PROCUREMENT_REQUEST
FOR EACH ROW
BEGIN
    IF NEW.Status = 'Approved' AND OLD.Status <> 'Approved' THEN
        INSERT INTO BUDGET_LOG (Log_ID, Category, Dept_ID, Request_ID, Admin_ID, Amount, Timestamp)
        VALUES (
            CONCAT('BL', LPAD(FLOOR(RAND()*999999),6,'0')),
            'Request Approved Automatically Logged',
            NEW.Dept_ID,
            NEW.Request_ID,
            NEW.Approval_Authority,
            NEW.Total_Cost,
            NOW()
        );
    END IF;
END$$


# T6 After product marked imported
CREATE TRIGGER trg_after_product_import
AFTER UPDATE ON PRODUCT
FOR EACH ROW
BEGIN
    IF NEW.Country_of_origin <> 'India' AND OLD.Country_of_origin = 'India' THEN
        INSERT INTO BUDGET_LOG (Log_ID, Category, Request_ID, Amount, Timestamp)
        VALUES (
            CONCAT('BL', LPAD(FLOOR(RAND()*999999),6,'0')),
            CONCAT('Product Imported: ', NEW.Item_ID),
            NULL,
            0,
            NOW()
        );
    END IF;
END$$


# T7 Prevent vendor deletion if products exist
CREATE TRIGGER trg_before_vendor_delete
BEFORE DELETE ON VENDOR
FOR EACH ROW
BEGIN
    IF EXISTS (SELECT 1 FROM PRODUCT WHERE Vendor_ID = OLD.Vendor_ID) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cannot delete vendor with active products.';
    END IF;
END$$

DELIMITER ;

# TEST Queries
SELECT calc_total_cost('PRO0001', 3);

CALL create_procurement_request('REQ0007','DPT001','PRO0001','VEN001',5);
CALL approve_request('REQ0007','ADM001');
CALL cancel_request('REQ0007','ADM001','Project cancelled');
CALL blacklist_vendor('VEN002','ADM001','Non-compliance');

SELECT get_department_efficiency('DPT001') AS 'Dept Efficiency %';
SELECT avg_vendor_contract_duration() AS 'Avg Vendor Contract Days';
SELECT get_pending_requests_count('DPT001') AS 'Pending Requests';

CALL log_contract_renewal('VEN001', '2030-12-31', 'ADM001');
CALL auto_restock_product('PROD001', 10, 50);

# Trigger trg_after_request_approval -- (Run this update on an existing request to fire the trigger)
UPDATE PROCUREMENT_REQUEST
SET Status = 'Approved',
    Approval_Authority = 'ADM001'
WHERE Request_ID = 'REQ001';

# Trigger trg_after_product_import
UPDATE PRODUCT
SET Country_of_origin = 'France'
WHERE Item_ID = 'PROD002';