from sqlalchemy import create_engine

# SQL Server Details
DB_SERVER = 'DESKTOP-FTK8MMV'
DB_NAME = 'IndusWeaveHR'

# Windows Authentication Connection
CONN_STR = f"mssql+pyodbc://@{DB_SERVER}/{DB_NAME}?driver=ODBC+Driver+17+for+SQL+Server&TrustServerCertificate=yes&trusted_connection=yes"

def get_engine():
    return create_engine(CONN_STR)

# Data folder ka path ab data-hackathon ke andar ja raha hai
RAW_DATA_PATH = r"D:\data rw\data-hackathon"