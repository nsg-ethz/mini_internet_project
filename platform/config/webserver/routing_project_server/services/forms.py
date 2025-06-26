from flask_wtf import FlaskForm
from wtforms import PasswordField, StringField, SubmitField, HiddenField, BooleanField, validators

class LoginForm(FlaskForm):
    username = StringField('Username', validators=[validators.InputRequired()])
    password = PasswordField('Password', validators=[validators.InputRequired()])
    submit = SubmitField('Submit')

class PeerForm(FlaskForm):
    peer_id = HiddenField("Peer id")
    peer_name = StringField(
        'Peer Name', 
        validators=[validators.DataRequired(message="Device name is required"), validators.Length(max=50, message="Name must be 50 characters or fewer")]
    )
    in_use = HiddenField("In Use")
    ip_address = StringField('IP Address', validators=[validators.Optional()])
    qr_image = StringField('QR Code Image', validators=[validators.Optional()])
    lastSeen = StringField('lastSeen', validators=[validators.Optional()])
    isConnected = BooleanField('isConnected', validators=[validators.Optional()])
    transferRxUnits = StringField('transferRxUnits', validators=[validators.Optional()])
    transferTxUnits = StringField('transferTxUnits', validators=[validators.Optional()])
    endpoint = StringField('endpoint', validators=[validators.Optional()])

    @classmethod
    def from_dict(cls, data):
        """Construct from dict with keys: 'id', 'peer_name', 'in_use', 'ip_address', 'qrcode_image'."""
        # Create an instance of the form with pre-populated data
        return cls(data={
            'peer_id': data['id'],
            'peer_name': data['peer_name'],
            'in_use': data['in_use'],
            'ip_address': data.get('ip_address', ''),
            'qr_image': data.get('qr_image', ''),
            'lastSeen': data.get('lastSeen', 'Never'),
            'isConnected': data.get('isConnected', 0),
            'transferRxUnits': data.get('transferRxUnits', '0 B'),
            'transferTxUnits': data.get('transferTxUnits', '0 B'),
            'endpoint': data.get('endpoint', ''),
        })
