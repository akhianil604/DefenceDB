# MINISTRY Table
CREATE TABLE MINISTRY (
    Admin_ID VARCHAR(6) UNIQUE, # Format of the key: FIN001, DEF001 etc.
    Name VARCHAR(100) NOT NULL,
    Role VARCHAR(50),
    Email VARCHAR(100) UNIQUE,
    Phone VARCHAR(20),
    Timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    Current_Budget DECIMAL(15,2),
    PRIMARY KEY (Admin_ID, Email)
);

# DEPARTMENT Table
CREATE TABLE DEPARTMENT (
    Dept_ID VARCHAR(6) UNIQUE, # Format: ARM001, AIR001, NAV001
    Name VARCHAR(100) NOT NULL,
    Location VARCHAR(100),
    Budget_Allocation DECIMAL(15,2),
    Current_Budget DECIMAL(15,2),
    Email VARCHAR(100) UNIQUE,
    Region VARCHAR(50),
    Timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (Dept_ID, Email)
);

# VENDOR Table
CREATE TABLE VENDOR (
    Vendor_ID VARCHAR(6) UNIQUE PRIMARY KEY, # Format: VEN001
    Company VARCHAR(100) NOT NULL,
    Category VARCHAR(50) CHECK (Category IN ('Vehicles', 'Ammunition', 'IT & Communication', 'Cybersecurity', 
    'Uniforms & Gear', 'Medical', 'Others')),
    Country VARCHAR(50),
    Email VARCHAR(100) UNIQUE,
    Phone VARCHAR(20),
    Blacklisted BOOLEAN DEFAULT FALSE,
    Contract_Expiry_Date DATE
);

# PRODUCT Table 
CREATE TABLE PRODUCT (
    Item_ID VARCHAR(7) UNIQUE PRIMARY KEY, # Format: PRO0001
    Name VARCHAR(100) NOT NULL,
    Category VARCHAR(50) NOT NULL,
    Unit_Cost DECIMAL(12,2) NOT NULL,
    Manufacturer VARCHAR(100),
    Country_of_Origin VARCHAR(50),
    Imported BOOLEAN DEFAULT FALSE,
    Stock_Available INT CHECK (Stock_Available >= 0),
    Vendor_ID  VARCHAR(6), FOREIGN KEY (Vendor_ID) REFERENCES VENDOR(Vendor_ID),
    # Ensure product category is valid for the vendor’s category
    CONSTRAINT chk_product_category CHECK (
        (Category IN ('Tanks','Armored Trucks','Fighter Jets','Submarines','Drones','Transport Aircraft') AND
            (SELECT Category FROM VENDOR WHERE VENDOR.Vendor_ID = PRODUCT.Vendor_ID) = 'Vehicles')
        OR
        (Category IN ('Rifles','Missiles','Artillery System','Air-defence systems') AND
            (SELECT Category FROM VENDOR WHERE VENDOR.Vendor_ID = PRODUCT.Vendor_ID) = 'Ammounition')
        OR
        (Category IN ('Radios','Satellite Phones','Secure Routers','Command Servers','Radar installations') AND
            (SELECT Category FROM VENDOR WHERE VENDOR.Vendor_ID = PRODUCT.Vendor_ID) = 'IT & Communication')
        OR
        (Category IN ('Firewalls','Threat monitoring platforms','Data centers') AND
            (SELECT Category FROM VENDOR WHERE VENDOR.Vendor_ID = PRODUCT.Vendor_ID) = 'Cybersecurity')
        OR
        (Category IN ('Helmets','Defence suits','Uniform') AND
            (SELECT Category FROM VENDOR WHERE VENDOR.Vendor_ID = PRODUCT.Vendor_ID) = 'Uniforms & Gear')
        OR
        (Category IN ('First-aid kits','Medical drones','Surgical instruments') AND
            (SELECT Category FROM VENDOR WHERE VENDOR.Vendor_ID = PRODUCT.Vendor_ID) = 'Medical')
        OR
        (Category = 'Others')
    )
);

# PROCUREMENT_REQUEST Table
CREATE TABLE PROCUREMENT_REQUEST (
    Request_ID VARCHAR(10) UNIQUE PRIMARY KEY, # Format: REQ0000001
    Dept_ID VARCHAR(6),
    Item_ID VARCHAR(7),
    Vendor_ID VARCHAR(6),
    Quantity INT CHECK (Quantity > 0),
    Total_Cost DECIMAL(15,2),
    Status VARCHAR(20) CHECK (Status IN ('Pending','Approved','Rejected')),
    Date_of_Request DATE NOT NULL,
    Approval_Authority VARCHAR(100),
    Date_of_Approval DATE,
    FOREIGN KEY (Dept_ID) REFERENCES DEPARTMENT(Dept_ID),
    FOREIGN KEY (Item_ID) REFERENCES PRODUCT(Item_ID),
    FOREIGN KEY (Vendor_ID) REFERENCES VENDOR(Vendor_ID)
);

# BUDGET_LOG Table
CREATE TABLE BUDGET_LOG (
    Log_ID VARCHAR(10) UNIQUE PRIMARY KEY, # Format: BUD0000001
    Category VARCHAR(50),
    Dept_ID VARCHAR(6),
    Request_ID VARCHAR(10),
    Admin_ID VARCHAR(6),
    Amount DECIMAL(15,2) NOT NULL,
    Timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (Dept_ID) REFERENCES DEPARTMENT(Dept_ID),
    FOREIGN KEY (Request_ID) REFERENCES PROCUREMENT_REQUEST(Request_ID),
    FOREIGN KEY (Admin_ID) REFERENCES MINISTRY(Admin_ID)
);
