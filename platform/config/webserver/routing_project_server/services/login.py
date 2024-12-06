import json
import bcrypt
import sqlite3
from flask import current_app
from flask_login import LoginManager, UserMixin, login_user
from flask_wtf.csrf import CSRFProtect
from pathlib import Path

csrf = CSRFProtect()
login_manager = LoginManager()

def login_init(app):
    csrf.init_app(app)

    login_manager.init_app(app)
    login_manager.login_view = "main.login"
    
    conn = sqlite3.connect(app.config['LOCATIONS']['vpn_db'])
    cursor = conn.cursor()
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS Users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL,
        passwd_hash TEXT NOT NULL,
        group_id TEXT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    conn.commit()
    cursor.execute("SELECT COUNT(*) FROM Users")
    user_count = cursor.fetchone()[0]
    conn.close()

    if user_count == 0:
        print(f"No users found in database. Parsing users from password files...")
        login_db_populate(app.config['LOCATIONS'])


def login_db_populate(locations):
    try:
        with open(Path(locations['vpn_passwd']), 'r') as file:
            user_data = json.load(file)
            
        for user in user_data:
            conn = sqlite3.connect(locations['vpn_db'])
            cursor = conn.cursor()
            cursor.execute('''
                INSERT INTO Users
                (username, passwd_hash, group_id)
                VALUES (?, ?, ?)
            ''',(
                user['username'], 
                bcrypt.hashpw(user['password'].encode('utf-8'), bcrypt.gensalt()), 
                user['group_id'])
            )
            conn.commit()
            conn.close()
    except Exception as e:
        print(f"Error when creating user database: {e}")

class User(UserMixin):
    username = None
    group_id = None
    def __init__(self, id, username, group_id):
        self.id = id
        self.username = username
        self.group_id = group_id

@login_manager.user_loader
def load_user(id) -> User:
    try:
        conn = sqlite3.connect(current_app.config['LOCATIONS']['vpn_db'])
        cursor = conn.cursor()
        cursor.execute("SELECT username, group_id FROM Users WHERE id = ?", (id,))
        result = cursor.fetchone()
        conn.close()

        if not result:
            print(f"Error: User  with id '{id}' not found.")
            return None

        return User(id, result[0], result[1])
    except Exception as e:
        print(f"Error when loading user: {e}")
    return None

def authenticate_user(username, password):
    """Check if the password for a user is correct."""
    try:
        conn = sqlite3.connect(current_app.config['LOCATIONS']['vpn_db'])
        cursor = conn.cursor()
        cursor.execute("SELECT id, passwd_hash FROM Users WHERE username = ?", (username,))
        result = cursor.fetchone()
        conn.close()

        if result and bcrypt.checkpw(password.encode('utf-8'), result[1]):
            user = load_user(result[0])
            login_user(user)
            return True
    except Exception as e:
        print(f"Error when chacking user '{username}' password: {e}")

    return False