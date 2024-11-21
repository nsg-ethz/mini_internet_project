from flask_login import LoginManager, UserMixin
from flask_wtf import FlaskForm
from flask_wtf.csrf import CSRFProtect
from wtforms import PasswordField, StringField, SubmitField
from wtforms import validators

# Initialize extensions without an app
csrf = CSRFProtect()
login_manager = LoginManager()

# Simulated database
users = {
    'user1': {'password': 'p1', 'group': 1},
    'user2': {'password': 'p2', 'group': 2},
    'user3': {'password': 'p3', 'group': 3},
}

# User model
class User(UserMixin):
    def __init__(self, id):
        self.id = id

# User loader
@login_manager.user_loader
def load_user(user_id):
    if user_id in users:
        return User(user_id)
    return None

def check_user_pwd(username: User, pwd):
    user = load_user(username)
    if user:
        if users[user.get_id()]['password'] == pwd:
            return True
    return False

# Login form
class LoginForm(FlaskForm):
    username = StringField('Username', validators=[validators.InputRequired()])
    password = PasswordField('Password', validators=[validators.InputRequired()])
    submit = SubmitField('Submit')
