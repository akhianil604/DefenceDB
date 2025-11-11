import os
from decimal import Decimal, ROUND_HALF_UP
from flask import Flask, render_template, request, redirect, url_for, flash
from flask import send_file
import csv
import io
from .db import get_db, query_all, query_scalar, exec_sql, transactional, close_db


def create_app():
    app = Flask(__name__)
    app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', 'dev-secret')
    # Ensure DB connection closes after each request
    app.teardown_appcontext(close_db)

    def export_csv(filename, columns, rows):
        si = io.StringIO()
        cw = csv.writer(si)
        cw.writerow(columns)
        for r in rows:
            cw.writerow([r.get(c) for c in columns])
        mem = io.BytesIO()
        mem.write(si.getvalue().encode('utf-8'))
        mem.seek(0)
        return send_file(mem, mimetype='text/csv', as_attachment=True, download_name=filename)

    @app.route('/')
    def dashboard():
        db = get_db()
        metrics = [
            ("Departments", "SELECT COUNT(*) FROM DEPARTMENT"),
            ("Vendors", "SELECT COUNT(*) FROM VENDOR"),
            ("Products", "SELECT COUNT(*) FROM PRODUCT"),
            ("Requests", "SELECT COUNT(*) FROM PROCUREMENT_REQUEST"),
            ("Approved Requests", "SELECT COUNT(*) FROM PROCUREMENT_REQUEST WHERE UPPER(Status)='APPROVED'"),
            ("Pending Requests", "SELECT COUNT(*) FROM PROCUREMENT_REQUEST WHERE UPPER(Status)='PENDING'"),
            ("Rejected Requests", "SELECT COUNT(*) FROM PROCUREMENT_REQUEST WHERE UPPER(Status)='REJECTED'"),
            ("Total Ministry Budget", "SELECT COALESCE(SUM(Current_Budget),0) FROM MINISTRY"),
            ("Total Dept Budget", "SELECT COALESCE(SUM(Current_Budget),0) FROM DEPARTMENT"),
        ]
        data = [(name, query_scalar(db, sql, default=0)) for name, sql in metrics]
        # Aggregate + nested subquery example: department spend vs remaining
        spend_rows = query_all(db, (
            "SELECT d.Dept_ID, d.Name, "
            "COALESCE((SELECT SUM(Amount) FROM BUDGET_LOG bl WHERE bl.Dept_ID=d.Dept_ID),0) AS Spent, "
            "COALESCE(d.Current_Budget,0) AS Remaining "
            "FROM DEPARTMENT d ORDER BY Spent DESC, d.Dept_ID LIMIT 15"
        ))
        return render_template('dashboard.html', metrics=data, spend_rows=spend_rows)

    @app.route('/ministry', methods=['GET','POST'])
    def ministry():
        db = get_db()
        if request.method == 'POST':
            # Create new official
            aid = request.form.get('admin_id','').strip()
            name = request.form.get('name','').strip()
            role = request.form.get('role','').strip()
            email = request.form.get('email','').strip()
            phone = request.form.get('phone','').strip()
            budget = request.form.get('current_budget','').strip()
            try:
                if not name or not email:
                    raise RuntimeError('Name and Email are required')
                if not aid:
                    nxt = int(query_scalar(db, "SELECT COALESCE(MAX(CAST(SUBSTRING(Admin_ID,4) AS UNSIGNED)),0)+1 FROM MINISTRY", default=1))
                    aid = f"DEF{nxt:03d}"
                if query_scalar(db, "SELECT COUNT(*) FROM MINISTRY WHERE Admin_ID=%s", (aid,), 0):
                    raise RuntimeError('Admin_ID already exists')
                exec_sql(db, "INSERT INTO MINISTRY (Admin_ID, Name, Role, Email, Phone, Current_Budget) VALUES (%s,%s,%s,%s,%s,%s)", (aid, name, role, email, phone, float(budget) if budget else 0))
                flash(f'Ministry official {name} ({aid}) created','success')
            except Exception as e:
                flash(str(e),'danger')
            return redirect(url_for('ministry'))
        q = request.args.get('q', '').strip()
        if q:
            like = f"%{q}%"
            rows = query_all(db, """
                SELECT Admin_ID,Name,Role,Email,Phone,Current_Budget,Timestamp
                FROM MINISTRY
                WHERE Admin_ID LIKE %s OR Name LIKE %s OR Role LIKE %s OR Email LIKE %s
                ORDER BY Admin_ID
            """, (like, like, like, like))
        else:
            rows = query_all(db, "SELECT Admin_ID,Name,Role,Email,Phone,Current_Budget,Timestamp FROM MINISTRY ORDER BY Admin_ID")
        if 'export' in request.args:
            return export_csv('ministry.csv', ["Admin_ID","Name","Role","Email","Phone","Current_Budget","Timestamp"], rows)
        return render_template('ministry.html', rows=rows, q=q)

    @app.route('/departments', methods=['GET','POST'])
    def departments():
        db = get_db()
        if request.method == 'POST':
            did = request.form.get('dept_id','').strip()
            name = request.form.get('name','').strip()
            location = request.form.get('location','').strip()
            alloc = request.form.get('budget_allocation','').strip()
            current = request.form.get('current_budget','').strip()
            email = request.form.get('email','').strip()
            region = request.form.get('region','').strip()
            try:
                if not name or not email:
                    raise RuntimeError('Name and Email are required')
                if not did:
                    nxt = int(query_scalar(db, "SELECT COALESCE(MAX(CAST(SUBSTRING(Dept_ID,4) AS UNSIGNED)),0)+1 FROM DEPARTMENT", default=1))
                    did = f"DPT{nxt:03d}"
                if query_scalar(db, "SELECT COUNT(*) FROM DEPARTMENT WHERE Dept_ID=%s", (did,), 0):
                    raise RuntimeError('Dept_ID already exists')
                # Default current budget to allocation when not provided
                alloc_val = float(alloc) if alloc else 0.0
                current_val = float(current) if current else alloc_val
                exec_sql(db, """
                    INSERT INTO DEPARTMENT (Dept_ID, Name, Location, Budget_Allocation, Current_Budget, Email, Region)
                    VALUES (%s,%s,%s,%s,%s,%s,%s)
                """, (did, name, location, alloc_val, current_val, email, region))
                flash(f'Department {name} ({did}) created','success')
            except Exception as e:
                flash(str(e),'danger')
            return redirect(url_for('departments'))
        q = request.args.get('q', '').strip()
        if q:
            like = f"%{q}%"
            rows = query_all(db, """
                SELECT Dept_ID,Name,Location,Budget_Allocation,Current_Budget,Email,Region,Timestamp
                FROM DEPARTMENT
                WHERE Dept_ID LIKE %s OR Name LIKE %s OR Region LIKE %s
                ORDER BY Dept_ID
            """, (like, like, like))
        else:
            rows = query_all(db, "SELECT Dept_ID,Name,Location,Budget_Allocation,Current_Budget,Email,Region,Timestamp FROM DEPARTMENT ORDER BY Dept_ID")
        if 'export' in request.args:
            return export_csv('departments.csv', ["Dept_ID","Name","Location","Budget_Allocation","Current_Budget","Email","Region","Timestamp"], rows)
        return render_template('departments.html', rows=rows, q=q)

    @app.route('/vendors', methods=['GET','POST'])
    def vendors():
        db = get_db()
        if request.method == 'POST':
            action = request.form.get('action')
            if action == 'blacklist':
                vid = request.form.get('vendor_id','').strip()
                aid = request.form.get('admin_id','').strip()
                if not (vid and aid):
                    flash('Provide Vendor_ID and Admin_ID','danger')
                else:
                    exists = query_scalar(db, "SELECT COUNT(*) FROM MINISTRY WHERE Admin_ID=%s", (aid,), 0)
                    if not exists:
                        flash('Unknown Admin_ID','danger')
                    else:
                        exec_sql(db, "UPDATE VENDOR SET Blacklisted=TRUE WHERE Vendor_ID=%s", (vid,))
                        flash(f'Vendor {vid} blacklisted','success')
                return redirect(url_for('vendors'))
            if action == 'create':
                vid = request.form.get('new_vendor_id','').strip()
                company = request.form.get('company','').strip()
                category = request.form.get('category','').strip()
                country = request.form.get('country','').strip()
                email = request.form.get('email','').strip()
                phone = request.form.get('phone','').strip()
                expiry = request.form.get('expiry','').strip()
                try:
                    if not company or not category:
                        raise RuntimeError('Company and Category are required')
                    if not vid:
                        nxt = int(query_scalar(db, "SELECT COALESCE(MAX(CAST(SUBSTRING(Vendor_ID,4) AS UNSIGNED)),0)+1 FROM VENDOR", default=1))
                        vid = f"VEN{nxt:03d}"
                    exec_sql(db, """
                        INSERT INTO VENDOR (Vendor_ID, Company, Category, Country, Email, Phone, Contract_Expiry_Date)
                        VALUES (%s,%s,%s,%s,%s,%s,%s)
                    """, (vid, company, category, country, email, phone, expiry if expiry else None))
                    flash(f'Vendor {company} ({vid}) created','success')
                except Exception as e:
                    flash(str(e),'danger')
                return redirect(url_for('vendors'))
        q = request.args.get('q', '').strip()
        if q:
            like = f"%{q}%"
            rows = query_all(db, """
                SELECT Vendor_ID,Company,Category,Country,Email,Phone,Blacklisted,Contract_Expiry_Date
                FROM VENDOR
                WHERE Vendor_ID LIKE %s OR Company LIKE %s OR Category LIKE %s OR Country LIKE %s
                ORDER BY Vendor_ID
            """, (like, like, like, like))
        else:
            rows = query_all(db, "SELECT Vendor_ID,Company,Category,Country,Email,Phone,Blacklisted,Contract_Expiry_Date FROM VENDOR ORDER BY Vendor_ID")
        if 'export' in request.args:
            return export_csv('vendors.csv', ["Vendor_ID","Company","Category","Country","Email","Phone","Blacklisted","Contract_Expiry_Date"], rows)
        return render_template('vendors.html', rows=rows, q=q)

    @app.route('/products', methods=['GET','POST'])
    def products():
        db = get_db()
        if request.method == 'POST':
            action = request.form.get('action')
            if action == 'restock':
                iid = request.form.get('item_id','').strip()
                qty = request.form.get('qty','').strip()
                if not (iid and qty.isdigit() and int(qty) > 0):
                    flash('Provide valid Item_ID and positive quantity','danger')
                else:
                    ex = query_scalar(db, "SELECT COUNT(*) FROM PRODUCT WHERE Item_ID=%s", (iid,), 0)
                    if not ex:
                        flash('Unknown Item_ID','danger')
                    else:
                        exec_sql(db, "UPDATE PRODUCT SET Stock_Available = Stock_Available + %s WHERE Item_ID=%s", (int(qty), iid))
                        flash(f'Restocked {iid} by {qty}','success')
                return redirect(url_for('products'))
            if action == 'create':
                iid = request.form.get('new_item_id','').strip()
                name = request.form.get('name','').strip()
                category = request.form.get('category','').strip()
                unit_cost = request.form.get('unit_cost','').strip()
                manufacturer = request.form.get('manufacturer','').strip()
                origin = request.form.get('origin','').strip()
                imported = True if request.form.get('imported') == 'on' else False
                stock = request.form.get('stock','').strip()
                vendor_id = request.form.get('vendor_id','').strip()
                try:
                    if not name or not category or not vendor_id:
                        raise RuntimeError('Name, Category and Vendor_ID are required')
                    if not iid:
                        nxt = int(query_scalar(db, "SELECT COALESCE(MAX(CAST(SUBSTRING(Item_ID,4) AS UNSIGNED)),0)+1 FROM PRODUCT", default=1))
                        iid = f"PRO{nxt:04d}"
                    if not query_scalar(db, "SELECT COUNT(*) FROM VENDOR WHERE Vendor_ID=%s", (vendor_id,), 0):
                        raise RuntimeError('Unknown Vendor_ID')
                    exec_sql(db, """
                        INSERT INTO PRODUCT (Item_ID, Name, Category, Unit_Cost, Manufacturer, Country_of_Origin, Imported, Stock_Available, Vendor_ID)
                        VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)
                    """, (iid, name, category, float(unit_cost) if unit_cost else 0, manufacturer, origin, imported, int(stock) if stock else 0, vendor_id))
                    flash(f'Product {name} ({iid}) created','success')
                except Exception as e:
                    flash(str(e),'danger')
                return redirect(url_for('products'))
        q = request.args.get('q', '').strip()
        if q:
            like = f"%{q}%"
            rows = query_all(db, """
                SELECT Item_ID,Name,Category,Unit_Cost,Manufacturer,Country_of_Origin,Imported,Stock_Available,Vendor_ID
                FROM PRODUCT
                WHERE Item_ID LIKE %s OR Name LIKE %s OR Category LIKE %s OR Manufacturer LIKE %s
                ORDER BY Item_ID
            """, (like, like, like, like))
        else:
            rows = query_all(db, "SELECT Item_ID,Name,Category,Unit_Cost,Manufacturer,Country_of_Origin,Imported,Stock_Available,Vendor_ID FROM PRODUCT ORDER BY Item_ID")
        if 'export' in request.args:
            return export_csv('products.csv', ["Item_ID","Name","Category","Unit_Cost","Manufacturer","Country_of_Origin","Imported","Stock_Available","Vendor_ID"], rows)
        return render_template('products.html', rows=rows, q=q)

    @app.route('/requests', methods=['GET','POST'])
    def requests_page():
        db = get_db()
        # Create request
        if request.method == 'POST' and request.form.get('action') == 'create':
            # Always auto-generate next Request_ID to ensure sequence
            rid = ''
            did = request.form.get('dept_id','').strip()
            iid = request.form.get('item_id','').strip()
            qty = request.form.get('qty','').strip()
            if not (did and iid and qty.isdigit() and int(qty)>0):
                flash('Invalid input for new request','danger')
            else:
                try:
                    with transactional(db):
                        # Resolve product and vendor
                        row = query_all(db, "SELECT Vendor_ID, Unit_Cost FROM PRODUCT WHERE Item_ID=%s FOR UPDATE", (iid,))
                        if not row:
                            raise RuntimeError('No supplier found for selected product')
                        vid = row[0]['Vendor_ID']
                        if vid is None or vid == '':
                            raise RuntimeError('Product has no linked vendor')
                        # Check vendor not blacklisted
                        black = query_scalar(db, "SELECT Blacklisted FROM VENDOR WHERE Vendor_ID=%s FOR UPDATE", (vid,), 0)
                        if black:
                            raise RuntimeError('Vendor is blacklisted')
                        # Generate the next Request_ID (lock table read)
                        nextn = int(query_scalar(db, "SELECT COALESCE(MAX(CAST(SUBSTRING(Request_ID,4) AS UNSIGNED)),0)+1 FROM PROCUREMENT_REQUEST FOR UPDATE", default=1))
                        rid = f"REQ{nextn:07d}"
                        total = query_scalar(db, "SELECT Unit_Cost * %s FROM PRODUCT WHERE Item_ID=%s", (int(qty), iid), 0) or 0
                        total_dec = Decimal(str(total)).quantize(Decimal('0.00000001'), rounding=ROUND_HALF_UP)
                        exec_sql(db, """
                            INSERT INTO PROCUREMENT_REQUEST
                            (Request_ID, Dept_ID, Item_ID, Vendor_ID, Quantity, Total_Cost, Status, Date_of_Request)
                            VALUES (%s,%s,%s,%s,%s,%s,'Pending', NOW())
                        """, (rid, did, iid, vid, int(qty), total_dec))
                    flash(f'Request {rid} created with vendor {vid}','success')
                except Exception as e:
                    flash(str(e), 'danger')
            # Redirect including the new id so the view can ensure it's visible
            return redirect(url_for('requests_page', new=rid))

        # Act on requests
        if request.method == 'POST' and request.form.get('action') in ('approve','reject','cancel'):
            action = request.form.get('action')
            rid = request.form.get('request_id','').strip()
            aid = request.form.get('admin_id','').strip()
            if not (rid and aid):
                flash('Provide Request_ID and Admin_ID','danger')
                return redirect(url_for('requests_page'))
            status = query_scalar(db, "SELECT Status FROM PROCUREMENT_REQUEST WHERE Request_ID=%s", (rid,))
            if status is None:
                flash('Unknown Request_ID','danger'); return redirect(url_for('requests_page'))
            if action == 'approve' and status != 'Pending':
                flash('Only Pending can be approved','danger'); return redirect(url_for('requests_page'))
            # New semantics: cancel only for Approved (undo approval)
            if action == 'cancel' and status != 'Approved':
                flash('Only Approved can be cancelled','danger'); return redirect(url_for('requests_page'))
            if action == 'reject' and status != 'Pending':
                flash('Only Pending can be rejected','danger'); return redirect(url_for('requests_page'))
            if not query_scalar(db, "SELECT COUNT(*) FROM MINISTRY WHERE Admin_ID=%s", (aid,), 0):
                flash('Unknown Admin_ID','danger'); return redirect(url_for('requests_page'))
            # Approve path (transactional updates)
            if action == 'approve':
                try:
                    with transactional(db):
                        r = query_all(db, "SELECT Dept_ID, Item_ID, Vendor_ID, Quantity, COALESCE(Total_Cost,0) Total_Cost FROM PROCUREMENT_REQUEST WHERE Request_ID=%s FOR UPDATE", (rid,))
                        if not r:
                            raise RuntimeError('Request not found')
                        did, iid, vid, qty, total = r[0]['Dept_ID'], r[0]['Item_ID'], r[0]['Vendor_ID'], int(r[0]['Quantity']), float(r[0]['Total_Cost'])
                        if total == 0:
                            total = query_scalar(db, "SELECT Unit_Cost * %s FROM PRODUCT WHERE Item_ID=%s", (qty, iid), 0) or 0
                        total_dec = Decimal(str(total)).quantize(Decimal('0.00000001'), rounding=ROUND_HALF_UP)
                        # Effective budget: prefer Current_Budget; if NULL, compute allocation minus approved spend
                        budget = query_scalar(db, "SELECT Current_Budget FROM DEPARTMENT WHERE Dept_ID=%s FOR UPDATE", (did,))
                        if budget is None:
                            budget = query_scalar(db, (
                                "SELECT COALESCE(d.Budget_Allocation,0) - COALESCE(SUM(pr2.Total_Cost),0) "
                                "FROM DEPARTMENT d LEFT JOIN PROCUREMENT_REQUEST pr2 ON pr2.Dept_ID=d.Dept_ID AND pr2.Status='Approved' "
                                "WHERE d.Dept_ID=%s GROUP BY d.Dept_ID"
                            ), (did,), 0)
                        budget = float(budget or 0)
                        stock = int(query_scalar(db, "SELECT Stock_Available FROM PRODUCT WHERE Item_ID=%s FOR UPDATE", (iid,), 0) or 0)
                        if budget < total:
                            raise RuntimeError('Insufficient department budget')
                        if stock < qty:
                            raise RuntimeError('Insufficient stock')
                        # Resolve admin name for Approval_Authority display
                        admin_name = query_scalar(db, "SELECT Name FROM MINISTRY WHERE Admin_ID=%s", (aid,), '') or aid
                        exec_sql(db, "UPDATE PRODUCT SET Stock_Available = Stock_Available - %s WHERE Item_ID=%s", (qty, iid))
                        exec_sql(db, "UPDATE DEPARTMENT SET Current_Budget = Current_Budget - %s WHERE Dept_ID=%s", (total_dec, did))
                        nextn = int(query_scalar(db, "SELECT COALESCE(MAX(CAST(SUBSTRING(Log_ID,4) AS UNSIGNED)),0)+1 FROM BUDGET_LOG", default=1))
                        log_id = f"BUD{nextn:07d}"
                        exec_sql(db, "INSERT INTO BUDGET_LOG (Log_ID, Category, Dept_ID, Request_ID, Admin_ID, Amount) VALUES (%s,%s,%s,%s,%s,%s)", (log_id, 'Procurement', did, rid, aid, total_dec))
                        exec_sql(db, "UPDATE PROCUREMENT_REQUEST SET Status='Approved', Date_of_Approval=NOW(), Approval_Authority=%s, Total_Cost=%s WHERE Request_ID=%s", (admin_name, total_dec, rid))
                    flash('Approved','success')
                except Exception as e:
                    flash(str(e),'danger')
                return redirect(url_for('requests_page'))
            # Cancel path (undo an approved request fully)
            if action == 'cancel':
                try:
                    with transactional(db):
                        # Lock the request and related rows
                        r = query_all(db, "SELECT Dept_ID, Item_ID, Quantity, COALESCE(Total_Cost,0) Total_Cost FROM PROCUREMENT_REQUEST WHERE Request_ID=%s FOR UPDATE", (rid,))
                        if not r:
                            raise RuntimeError('Request not found')
                        did, iid, qty, total = r[0]['Dept_ID'], r[0]['Item_ID'], int(r[0]['Quantity']), float(r[0]['Total_Cost'])
                        # Restore stock and department budget
                        exec_sql(db, "UPDATE PRODUCT SET Stock_Available = Stock_Available + %s WHERE Item_ID=%s", (qty, iid))
                        total_dec = Decimal(str(total)).quantize(Decimal('0.00000001'), rounding=ROUND_HALF_UP)
                        exec_sql(db, "UPDATE DEPARTMENT SET Current_Budget = Current_Budget + %s WHERE Dept_ID=%s", (total_dec, did))
                        # Write reversal entry in budget log (negative amount)
                        nextn = int(query_scalar(db, "SELECT COALESCE(MAX(CAST(SUBSTRING(Log_ID,4) AS UNSIGNED)),0)+1 FROM BUDGET_LOG", default=1))
                        log_id = f"BUD{nextn:07d}"
                        rev_amt = -abs(total_dec)
                        if rev_amt != 0:
                            exec_sql(db, "INSERT INTO BUDGET_LOG (Log_ID, Category, Dept_ID, Request_ID, Admin_ID, Amount) VALUES (%s,%s,%s,%s,%s,%s)", (log_id, 'Reversal', did, rid, aid, rev_amt))
                        # Finally remove the approved request entry
                        exec_sql(db, "DELETE FROM PROCUREMENT_REQUEST WHERE Request_ID=%s", (rid,))
                    flash('Cancelled and reverted successfully','success')
                except Exception as e:
                    flash(str(e),'danger')
                return redirect(url_for('requests_page'))
            # Reject (for Pending requests)
            admin_name = query_scalar(db, "SELECT Name FROM MINISTRY WHERE Admin_ID=%s", (aid,), '') or aid
            exec_sql(db, "UPDATE PROCUREMENT_REQUEST SET Status='Rejected', Date_of_Approval=NOW(), Approval_Authority=%s WHERE Request_ID=%s", (admin_name, rid))
            flash('Rejected','success')
            return redirect(url_for('requests_page'))

        # GET: render lists and forms
        q = request.args.get('q','').strip()
        sort = request.args.get('sort','desc').lower()
        sort = 'asc' if sort == 'asc' else 'desc'
        order_sql = 'ASC' if sort == 'asc' else 'DESC'
        cols = ["Request_ID","Dept_ID","Item_ID","Vendor_ID","Quantity","Total_Cost","Status","Date_of_Request","Approval_Authority","Date_of_Approval"]
        base = (
            "SELECT pr.Request_ID, pr.Dept_ID, pr.Item_ID, pr.Vendor_ID, pr.Quantity, pr.Total_Cost, pr.Status, "
            "pr.Date_of_Request, COALESCE(m.Name, pr.Approval_Authority) AS Approval_Authority, pr.Date_of_Approval "
            "FROM PROCUREMENT_REQUEST pr "
            "LEFT JOIN MINISTRY m ON pr.Approval_Authority = m.Admin_ID "
        )
        new_id = request.args.get('new','').strip()
        if q:
            like = f"%{q}%"
            rows = query_all(db, base + f"WHERE pr.Request_ID LIKE %s OR pr.Dept_ID LIKE %s OR pr.Status LIKE %s ORDER BY pr.Request_ID {order_sql}", (like, like, like))
        else:
            rows = query_all(db, base + f"ORDER BY pr.Request_ID {order_sql}")
        # Ensure just-created request is present even if not in default window
        if new_id and not any(r['Request_ID'] == new_id for r in rows):
            single = query_all(db, base + "WHERE pr.Request_ID=%s", (new_id,))
            if single:
                rows = (rows + single) if sort == 'asc' else (single + rows)
        if 'export' in request.args:
            return export_csv('requests.csv', cols, rows)
        depts = [r['Dept_ID'] for r in query_all(db, "SELECT Dept_ID FROM DEPARTMENT ORDER BY Dept_ID")]
        items = [r['Item_ID'] for r in query_all(db, "SELECT Item_ID FROM PRODUCT ORDER BY Item_ID")]
        officials = query_all(db, "SELECT Admin_ID, Name FROM MINISTRY ORDER BY Name")
        return render_template('requests.html', rows=rows, q=q, sort=sort, depts=depts, items=items, officials=officials)

    @app.route('/logs')
    def logs():
        q = request.args.get('q','').strip()
        db = get_db()
        if q:
            like = f"%{q}%"
            rows = query_all(db, """
                SELECT Log_ID,Category,Dept_ID,Request_ID,Admin_ID,Amount,Timestamp
                FROM BUDGET_LOG
                WHERE Log_ID LIKE %s OR Dept_ID LIKE %s OR Request_ID LIKE %s OR Admin_ID LIKE %s
                ORDER BY Timestamp DESC, Log_ID DESC
                LIMIT 1000
            """, (like, like, like, like))
        else:
            rows = query_all(db, "SELECT Log_ID,Category,Dept_ID,Request_ID,Admin_ID,Amount,Timestamp FROM BUDGET_LOG ORDER BY Timestamp DESC, Log_ID DESC LIMIT 1000")
        if 'export' in request.args:
            return export_csv('budget_log.csv', ["Log_ID","Category","Dept_ID","Request_ID","Admin_ID","Amount","Timestamp"], rows)
        return render_template('logs.html', rows=rows, q=q)

    @app.route('/analytics')
    def analytics():
        db = get_db()
        # 1) Department KPIs with joins + conditional aggregates + nested spend
        dept_kpis = query_all(db, """
            SELECT d.Dept_ID, d.Name,
                   COUNT(pr.Request_ID) AS Total_Requests,
                   SUM(CASE WHEN UPPER(pr.Status)='APPROVED' THEN 1 ELSE 0 END) AS Approved,
                   SUM(CASE WHEN UPPER(pr.Status)='REJECTED' THEN 1 ELSE 0 END) AS Rejected,
                   SUM(CASE WHEN UPPER(pr.Status)='PENDING'  THEN 1 ELSE 0 END) AS Pending,
                   COALESCE((SELECT SUM(bl.Amount) FROM BUDGET_LOG bl WHERE bl.Dept_ID=d.Dept_ID),0) AS Total_Spend,
                   AVG(pr.Total_Cost) AS Avg_Request_Cost,
                   MAX(pr.Total_Cost) AS Max_Request_Cost
            FROM DEPARTMENT d
            LEFT JOIN PROCUREMENT_REQUEST pr ON pr.Dept_ID = d.Dept_ID
            GROUP BY d.Dept_ID, d.Name
            ORDER BY Total_Spend DESC, d.Dept_ID
        """)

        # 2) Category spend using join PR->PRODUCT and only approved requests
        cat_spend = query_all(db, """
            SELECT p.Category,
                   COUNT(pr.Request_ID) AS Requests,
                   SUM(CASE WHEN pr.Status='Approved' THEN pr.Total_Cost ELSE 0 END) AS Approved_Spend,
                   AVG(p.Unit_Cost) AS Avg_Unit_Cost
            FROM PRODUCT p
            LEFT JOIN PROCUREMENT_REQUEST pr ON pr.Item_ID = p.Item_ID
            GROUP BY p.Category
            ORDER BY Approved_Spend DESC, p.Category
        """)

        # 3) Vendor performance: product_count (subquery) + spend (join logs)
        vendor_perf = query_all(db, """
            SELECT v.Vendor_ID, v.Company,
                   (SELECT COUNT(*) FROM PRODUCT px WHERE px.Vendor_ID = v.Vendor_ID) AS Product_Count,
                   COALESCE(SUM(bl.Amount),0) AS Total_Spend
            FROM VENDOR v
            LEFT JOIN PROCUREMENT_REQUEST pr ON pr.Vendor_ID = v.Vendor_ID AND pr.Status='Approved'
            LEFT JOIN BUDGET_LOG bl ON bl.Request_ID = pr.Request_ID
            GROUP BY v.Vendor_ID, v.Company
            ORDER BY Total_Spend DESC, Product_Count DESC
        """)

        # 4) Departments whose spend is above average department spend (nested subquery + HAVING)
        above_avg_dept = query_all(db, """
            SELECT d.Dept_ID, d.Name,
                   COALESCE((SELECT SUM(Amount) FROM BUDGET_LOG bl WHERE bl.Dept_ID=d.Dept_ID),0) AS Spend
            FROM DEPARTMENT d
            HAVING Spend > (
                SELECT AVG(x.sum_amt) FROM (
                    SELECT COALESCE(SUM(Amount),0) AS sum_amt
                    FROM BUDGET_LOG bl2
                    RIGHT JOIN DEPARTMENT d2 ON d2.Dept_ID = bl2.Dept_ID
                    GROUP BY d2.Dept_ID
                ) x
            )
            ORDER BY Spend DESC
        """)

        # 5) High value approvals with join to vendor + ministry via budget_log
        high_value = query_all(db, """
            SELECT pr.Request_ID, pr.Dept_ID, pr.Item_ID, pr.Vendor_ID, pr.Total_Cost,
                   v.Company AS Vendor, m.Name AS Approved_By, pr.Date_of_Approval
            FROM PROCUREMENT_REQUEST pr
            LEFT JOIN VENDOR v ON v.Vendor_ID = pr.Vendor_ID
            LEFT JOIN BUDGET_LOG bl ON bl.Request_ID = pr.Request_ID
            LEFT JOIN MINISTRY m ON m.Admin_ID = bl.Admin_ID
            WHERE pr.Status='Approved'
            ORDER BY pr.Total_Cost DESC
            LIMIT 20
        """)

        return render_template('analytics.html',
                               dept_kpis=dept_kpis,
                               cat_spend=cat_spend,
                               vendor_perf=vendor_perf,
                               above_avg_dept=above_avg_dept,
                               high_value=high_value)

    return app


if __name__ == '__main__':
    app = create_app()
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 5000)), debug=True)
