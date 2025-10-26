CREATE DATABASE IF NOT EXISTS defense_db;
USE defense_db;

			# 1. MINISTRY
# Primary Key: (Admin_ID, Email)
# UNIQUE: Admin_ID, Email
CREATE TABLE MINISTRY (
    Admin_ID VARCHAR(6) NOT NULL UNIQUE, # Format: FIN001, DEF001 etc.
    Name VARCHAR(100) NOT NULL, # Full name of ministry official
    Role VARCHAR(50), # Role or designation
    Email VARCHAR(100) NOT NULL UNIQUE, # Must be unique
    Phone VARCHAR(20),
    Timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    Current_Budget DECIMAL(20,8), # Changed precision from (15,2)
    PRIMARY KEY (Admin_ID, Email)
);

			# 2. DEPARTMENT
# Primary Key: (Dept_ID, Email)
# UNIQUE: Dept_ID, Email
CREATE TABLE DEPARTMENT (
    Dept_ID VARCHAR(6) NOT NULL UNIQUE, # Format: ARM001, AIR001, NAV001 etc.
    Name VARCHAR(100) NOT NULL,
    Location VARCHAR(100),
    Budget_Allocation DECIMAL(20,8),
    Current_Budget DECIMAL(20,8),
    Email VARCHAR(100) UNIQUE,
    Region VARCHAR(50),
    Timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (Dept_ID, Email)
);

			# 3. VENDOR
# Primary Key: Vendor_ID
# UNIQUE: Email
# CHECK: Valid category
CREATE TABLE VENDOR (
    Vendor_ID VARCHAR(6) NOT NULL PRIMARY KEY, # Format: VEN001, VEN002 etc.
    Company VARCHAR(100) NOT NULL,
    Category VARCHAR(50) CHECK (Category IN (
        'Vehicles',
        'Ammunition',
        'IT & Communication',
        'Cybersecurity',
        'Uniforms & Gear',
        'Medical',
        'Others'
    )),
    Country VARCHAR(50),
    Email VARCHAR(100) UNIQUE,
    Phone VARCHAR(20),
    Blacklisted BOOLEAN DEFAULT FALSE,
    Contract_Expiry_Date DATE
);

			# 4. PRODUCT 
# Primary Key: Item_ID
# Foreign Key: Vendor_ID to VENDOR(Vendor_ID)
# CHECK: Valid product category
CREATE TABLE PRODUCT (
    Item_ID VARCHAR(7) NOT NULL UNIQUE PRIMARY KEY, # Format: PRO0001, PRO0002, etc.
    Name VARCHAR(100) NOT NULL,
    Category VARCHAR(50) NOT NULL,
    Unit_Cost DECIMAL(12,2) NOT NULL,
    Manufacturer VARCHAR(100),
    Country_of_Origin VARCHAR(50),
    Imported BOOLEAN DEFAULT FALSE,
    Stock_Available INT CHECK (Stock_Available >= 0),
    Vendor_ID VARCHAR(6),
    FOREIGN KEY (Vendor_ID) REFERENCES VENDOR(Vendor_ID)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT chk_product_category CHECK (
        Category IN (
            'Tanks','Armored Trucks','Fighter Jets','Submarines','Drones','Transport Aircraft',
            'Rifles','Missiles','Artillery System','Air-defence systems',
            'Radios','Satellite Phones','Secure Routers','Command Servers','Radar installations',
            'Firewalls','Threat monitoring platforms','Data centers',
            'Helmets','Defence suits','Uniform',
            'First-aid kits','Medical drones','Surgical instruments',
            'Others'
        )
    )
);

			# 5. PROCUREMENT_REQUEST
# Primary Key: Request_ID
# Foreign Key 1: Dept_ID to DEPARTMENT(Dept_ID)
# Foreign Key 2: Item_ID to PRODUCT(Item_ID)
# Foreign Key 3: Vendor_ID toVENDOR(Vendor_ID)
# CHECK: Quantity > 0, Status valid
CREATE TABLE PROCUREMENT_REQUEST (
    Request_ID VARCHAR(10) NOT NULL UNIQUE PRIMARY KEY, -- Format: REQ0000001
    Dept_ID VARCHAR(6),
    Item_ID VARCHAR(7),
    Vendor_ID VARCHAR(6),
    Quantity INT CHECK (Quantity > 0),
    Total_Cost DECIMAL(15,2),
    Status VARCHAR(20) CHECK (Status IN ('Pending', 'Approved', 'Rejected')),
    Date_of_Request DATE NOT NULL,
    Approval_Authority VARCHAR(100),
    Date_of_Approval DATE,
    FOREIGN KEY (Dept_ID) REFERENCES DEPARTMENT(Dept_ID)
        ON DELETE SET NULL
        ON UPDATE CASCADE,
    FOREIGN KEY (Item_ID) REFERENCES PRODUCT(Item_ID)
        ON DELETE SET NULL
        ON UPDATE CASCADE,
    FOREIGN KEY (Vendor_ID) REFERENCES VENDOR(Vendor_ID)
        ON DELETE SET NULL
        ON UPDATE CASCADE
);

			# 6. BUDGET_LOG
# Primary Key: Log_ID
# Foreign Key 1: Dept_ID to DEPARTMENT(Dept_ID)
# Foreign Key 2: Request_ID to PROCUREMENT_REQUEST(Request_ID)
# Foreign Key 3: Admin_ID to MINISTRY(Admin_ID)
CREATE TABLE BUDGET_LOG (
    Log_ID VARCHAR(10) NOT NULL UNIQUE PRIMARY KEY, # Format: BUD0000001
    Category VARCHAR(50), # "Defense", "R&D", "Procurement"
    Dept_ID VARCHAR(6),
    Request_ID VARCHAR(10),
    Admin_ID VARCHAR(6),
    Amount DECIMAL(20,8) NOT NULL, # Changed from (15,2)
    Timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (Dept_ID) REFERENCES DEPARTMENT(Dept_ID)
        ON DELETE SET NULL
        ON UPDATE CASCADE,
    FOREIGN KEY (Request_ID) REFERENCES PROCUREMENT_REQUEST(Request_ID)
        ON DELETE SET NULL
        ON UPDATE CASCADE,
    FOREIGN KEY (Admin_ID) REFERENCES MINISTRY(Admin_ID)
        ON DELETE SET NULL
        ON UPDATE CASCADE
);

ALTER TABLE DEPARTMENT MODIFY Current_Budget DECIMAL(20,8);
ALTER TABLE DEPARTMENT MODIFY Budget_Allocation DECIMAL(20,8);
ALTER TABLE MINISTRY MODIFY Current_Budget DECIMAL(20,8);
ALTER TABLE BUDGET_LOG MODIFY Amount DECIMAL(20,8);