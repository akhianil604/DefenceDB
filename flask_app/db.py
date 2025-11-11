import os
import mysql.connector as mysql
from contextlib import contextmanager
from flask import g, has_app_context


def _conn_params():
    # Support multiple common env var names
    host = os.environ.get('DB_HOST', os.environ.get('MYSQL_HOST', 'localhost'))
    user = os.environ.get('DB_USER', os.environ.get('MYSQL_USER', 'root'))
    password = os.environ.get('DB_PASSWORD', os.environ.get('MYSQL_PASSWORD', ''))
    port = int(os.environ.get('DB_PORT', os.environ.get('MYSQL_PORT', '3306')))
    database = os.environ.get('DB_NAME', os.environ.get('MYSQL_DATABASE', 'defense_db'))
    return dict(host=host, user=user, password=password, port=port, database=database)


def get_db():
    # Reuse one connection per request/app context
    if has_app_context() and hasattr(g, 'db_conn') and g.db_conn:
        return g.db_conn
    cfg = _conn_params()
    try:
        conn = mysql.connect(
            host=cfg['host'],
            user=cfg['user'],
            password=cfg['password'],
            port=cfg['port'],
            database=cfg['database'],
            autocommit=True,
            allow_local_infile=True,
        )
        try:
            conn.set_charset_collation('utf8mb4')
        except Exception:
            pass
    except mysql.Error as e:
        hint = (
            "MySQL connection failed. Set DB_* env vars, e.g. DB_HOST, DB_USER, DB_PASSWORD, DB_NAME. "
            f"Tried host={cfg['host']} user={cfg['user']} db={cfg['database']}"
        )
        raise RuntimeError(f"{e}; {hint}") from e
    if has_app_context():
        g.db_conn = conn
    return conn


def close_db(_=None):
    if hasattr(g, 'db_conn') and g.db_conn:
        try:
            g.db_conn.close()
        finally:
            g.db_conn = None


def query_all(conn, sql, params=None):
    cur = conn.cursor(dictionary=True)
    cur.execute(sql, params or ())
    rows = cur.fetchall()
    cur.close()
    return rows


def query_scalar(conn, sql, params=None, default=None):
    cur = conn.cursor()
    cur.execute(sql, params or ())
    row = cur.fetchone()
    cur.close()
    if not row:
        return default
    return row[0]


def exec_sql(conn, sql, params=None):
    cur = conn.cursor()
    cur.execute(sql, params or ())
    cur.close()
    # Ensure data-changing statements persist even if autocommit is toggled
    try:
        conn.commit()
    except Exception:
        pass


@contextmanager
def transactional(conn):
    try:
        conn.start_transaction()
        yield
        conn.commit()
    except Exception:
        conn.rollback()
        raise
