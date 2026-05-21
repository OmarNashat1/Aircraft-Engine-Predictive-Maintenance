IF DB_ID('backendengine') IS NULL
BEGIN
    CREATE DATABASE backendengine;
END
GO

USE backendengine;
GO

IF OBJECT_ID('alert', 'U') IS NOT NULL DROP TABLE alert;
IF OBJECT_ID('report', 'U') IS NOT NULL DROP TABLE report;
IF OBJECT_ID('prediction', 'U') IS NOT NULL DROP TABLE prediction;
IF OBJECT_ID('engine_data', 'U') IS NOT NULL DROP TABLE engine_data;
IF OBJECT_ID('audit_log', 'U') IS NOT NULL DROP TABLE audit_log;
IF OBJECT_ID('users', 'U') IS NOT NULL DROP TABLE users;
IF OBJECT_ID('engine', 'U') IS NOT NULL DROP TABLE engine;
GO

CREATE TABLE users (
    user_id INT PRIMARY KEY IDENTITY(1,1),
    username VARCHAR(100) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL
);
GO

CREATE TABLE audit_log (
    log_id INT PRIMARY KEY IDENTITY(1,1),
    user_id INT NOT NULL,
    login_time DATETIME NOT NULL,
    timestamp DATETIME NOT NULL DEFAULT GETDATE(),

    CONSTRAINT FK_audit_users 
        FOREIGN KEY (user_id) REFERENCES users(user_id)
);
GO

CREATE TABLE engine (
    engine_id INT PRIMARY KEY,
    status VARCHAR(50) NOT NULL,
    rul FLOAT NULL,
    timestamp DATETIME NOT NULL DEFAULT GETDATE(),
    cycle_id INT NULL
);
GO

CREATE TABLE engine_data (
    engine_id INT NOT NULL,
    cycle_id INT NOT NULL,
    timestep INT NOT NULL,
    file_path VARCHAR(500) NULL,

    alt FLOAT NULL,
    Mach FLOAT NULL,
    TRA FLOAT NULL,
    T2 FLOAT NULL,
    T24 FLOAT NULL,
    T30 FLOAT NULL,
    T48 FLOAT NULL,
    T50 FLOAT NULL,
    P15 FLOAT NULL,
    P2 FLOAT NULL,
    P21 FLOAT NULL,
    P24 FLOAT NULL,
    Ps30 FLOAT NULL,
    P40 FLOAT NULL,
    P50 FLOAT NULL,
    Nf FLOAT NULL,
    Nc FLOAT NULL,
    Wf FLOAT NULL,

    CONSTRAINT PK_engine_data 
        PRIMARY KEY (engine_id, cycle_id, timestep),

    CONSTRAINT FK_engine_data_engine 
        FOREIGN KEY (engine_id) REFERENCES engine(engine_id)
);
GO

CREATE TABLE prediction (
    prediction_id INT PRIMARY KEY IDENTITY(1,1),

    engine_id INT NOT NULL,
    cycle_id INT NOT NULL,
    data_timestep INT NOT NULL,

    predicted_rul FLOAT NULL,
    probability FLOAT NULL,
    health_status VARCHAR(20) NULL,
    top_features NVARCHAR(MAX) NULL,
    predicted_at DATETIME NOT NULL DEFAULT GETDATE(),

    CONSTRAINT FK_prediction_engine
        FOREIGN KEY (engine_id) REFERENCES engine(engine_id),

    CONSTRAINT FK_prediction_engine_data 
        FOREIGN KEY (engine_id, cycle_id, data_timestep)
        REFERENCES engine_data(engine_id, cycle_id, timestep)
);
GO

CREATE TABLE alert (
    alert_id INT PRIMARY KEY IDENTITY(1,1),
    prediction_id INT NOT NULL,
    alert_level VARCHAR(20) NOT NULL,
    message VARCHAR(500) NOT NULL,
    created_at DATETIME NOT NULL DEFAULT GETDATE(),
    is_resolved BIT NOT NULL DEFAULT 0,

    CONSTRAINT FK_alert_prediction 
        FOREIGN KEY (prediction_id) REFERENCES prediction(prediction_id)
);
GO

CREATE TABLE report (
    report_id INT PRIMARY KEY IDENTITY(1,1),
    prediction_id INT NOT NULL,
    engine_id INT NOT NULL,
    file_path VARCHAR(500) NOT NULL,
    report_textfile NVARCHAR(MAX) NULL,
    created_at DATETIME NOT NULL DEFAULT GETDATE(),

    CONSTRAINT FK_report_prediction
        FOREIGN KEY (prediction_id) REFERENCES prediction(prediction_id),

    CONSTRAINT FK_report_engine 
        FOREIGN KEY (engine_id) REFERENCES engine(engine_id)
);
GO
