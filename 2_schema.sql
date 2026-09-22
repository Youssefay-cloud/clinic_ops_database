-- ============================================================================
-- CLINIC APPOINTMENT LEDGER - DDL SCHEMA DEFINITION
-- Engine: MySQL 8.0+ (InnoDB)
-- ============================================================================

-- Clean teardown for local testing
DROP TABLE IF EXISTS billing_ledger;
DROP TABLE IF EXISTS appointment_audit_log;
DROP TABLE IF EXISTS appointment_services;
DROP TABLE IF EXISTS appointments;
DROP TABLE IF EXISTS services;
DROP TABLE IF EXISTS patients;
DROP TABLE IF EXISTS doctor_schedules;
DROP TABLE IF EXISTS doctors;
DROP TABLE IF EXISTS rooms;
DROP TABLE IF EXISTS branches;

-- ============================================================================
-- 1. CLINIC INFRASTRUCTURE & STAFF
-- ============================================================================

CREATE TABLE branches (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(150) NOT NULL,
    address VARCHAR(255),
    phone VARCHAR(30),
    timezone VARCHAR(50) NOT NULL DEFAULT 'UTC',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE rooms (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    branch_id BIGINT NOT NULL,
    room_number VARCHAR(20) NOT NULL,
    room_type VARCHAR(50) NOT NULL DEFAULT 'general_exam',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_rooms_branch FOREIGN KEY (branch_id) 
        REFERENCES branches(id) ON DELETE RESTRICT,
    CONSTRAINT uk_branch_room UNIQUE (branch_id, room_number)
) ENGINE=InnoDB;

CREATE TABLE doctors (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    full_name VARCHAR(150) NOT NULL,
    license_number VARCHAR(50) NOT NULL UNIQUE,
    specialty VARCHAR(80) NOT NULL,
    commission_rate DECIMAL(5, 2) NOT NULL DEFAULT 0.20,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_commission_rate CHECK (commission_rate >= 0.00 AND commission_rate <= 1.00)
) ENGINE=InnoDB;

CREATE TABLE doctor_schedules (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    doctor_id BIGINT NOT NULL,
    branch_id BIGINT NOT NULL,
    day_of_week TINYINT NOT NULL, -- 1=Monday, 7=Sunday
    shift_start TIME NOT NULL,
    shift_end TIME NOT NULL,
    CONSTRAINT fk_schedules_doctor FOREIGN KEY (doctor_id) 
        REFERENCES doctors(id) ON DELETE CASCADE,
    CONSTRAINT fk_schedules_branch FOREIGN KEY (branch_id) 
        REFERENCES branches(id) ON DELETE CASCADE,
    CONSTRAINT chk_day_of_week CHECK (day_of_week BETWEEN 1 AND 7),
    CONSTRAINT chk_shift_time_window CHECK (shift_end > shift_start),
    CONSTRAINT uk_doctor_day_shift UNIQUE (doctor_id, branch_id, day_of_week, shift_start)
) ENGINE=InnoDB;

-- ============================================================================
-- 2. PATIENT RECORDS & SERVICES CATALOG
-- ============================================================================

CREATE TABLE patients (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    mrn VARCHAR(50) NOT NULL UNIQUE, -- Medical Record Number
    full_name VARCHAR(150) NOT NULL,
    date_of_birth DATE NOT NULL,
    phone VARCHAR(30) NOT NULL,
    emergency_contact VARCHAR(150),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE services (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    service_code VARCHAR(30) NOT NULL UNIQUE,
    description VARCHAR(200) NOT NULL,
    standard_fee DECIMAL(10, 2) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_service_fee CHECK (standard_fee >= 0.00)
) ENGINE=InnoDB;

-- ============================================================================
-- 3. CORE APPOINTMENTS
-- ============================================================================

CREATE TABLE appointments (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    patient_id BIGINT NOT NULL,
    doctor_id BIGINT NOT NULL,
    room_id BIGINT NOT NULL,
    start_time DATETIME NOT NULL,
    end_time DATETIME NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'scheduled',
    cancellation_reason TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_appointments_patient FOREIGN KEY (patient_id) 
        REFERENCES patients(id) ON DELETE RESTRICT,
    CONSTRAINT fk_appointments_doctor FOREIGN KEY (doctor_id) 
        REFERENCES doctors(id) ON DELETE RESTRICT,
    CONSTRAINT fk_appointments_room FOREIGN KEY (room_id) 
        REFERENCES rooms(id) ON DELETE RESTRICT,
    CONSTRAINT chk_appointment_window CHECK (end_time > start_time),
    CONSTRAINT chk_appointment_status CHECK (
        status IN ('scheduled', 'confirmed', 'in_progress', 'completed', 'cancelled', 'no_show')
    )
) ENGINE=InnoDB;

CREATE TABLE appointment_services (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    appointment_id BIGINT NOT NULL,
    service_id BIGINT NOT NULL,
    billed_fee DECIMAL(10, 2) NOT NULL,
    CONSTRAINT fk_as_appointment FOREIGN KEY (appointment_id) 
        REFERENCES appointments(id) ON DELETE CASCADE,
    CONSTRAINT fk_as_service FOREIGN KEY (service_id) 
        REFERENCES services(id) ON DELETE RESTRICT,
    CONSTRAINT uk_appointment_service UNIQUE (appointment_id, service_id),
    CONSTRAINT chk_billed_fee CHECK (billed_fee >= 0.00)
) ENGINE=InnoDB;

-- ============================================================================
-- 4. AUDIT & FINANCIAL LEDGER
-- ============================================================================

CREATE TABLE appointment_audit_log (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    appointment_id BIGINT NOT NULL,
    changed_by_user VARCHAR(100) NOT NULL,
    action_type VARCHAR(20) NOT NULL, -- 'INSERT', 'UPDATE', 'CANCEL'
    old_status VARCHAR(30),
    new_status VARCHAR(30),
    previous_start_time DATETIME,
    new_start_time DATETIME,
    previous_room_id BIGINT,
    new_room_id BIGINT,
    changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_audit_appointment FOREIGN KEY (appointment_id) 
        REFERENCES appointments(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE billing_ledger (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    appointment_id BIGINT NOT NULL UNIQUE, -- Enforces 1:1 relationship
    total_amount DECIMAL(12, 2) NOT NULL,
    patient_paid DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    insurance_paid DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    clinic_cut DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    doctor_commission DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    payment_status VARCHAR(30) NOT NULL DEFAULT 'unpaid',
    settled_at DATETIME,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_billing_appointment FOREIGN KEY (appointment_id) 
        REFERENCES appointments(id) ON DELETE RESTRICT,
    CONSTRAINT chk_total_amount CHECK (total_amount >= 0.00),
    CONSTRAINT chk_patient_paid CHECK (patient_paid >= 0.00),
    CONSTRAINT chk_insurance_paid CHECK (insurance_paid >= 0.00),
    CONSTRAINT chk_clinic_cut CHECK (clinic_cut >= 0.00),
    CONSTRAINT chk_doctor_commission CHECK (doctor_commission >= 0.00),
    CONSTRAINT chk_payment_status CHECK (
        payment_status IN ('unpaid', 'partially_paid', 'paid', 'refunded', 'waived')
    ),
    CONSTRAINT chk_settlement_split CHECK (total_amount = (clinic_cut + doctor_commission))
) ENGINE=InnoDB;

-- ============================================================================
-- 5. PERFORMANCE INDEXES
-- ============================================================================

CREATE INDEX idx_appointments_patient ON appointments(patient_id);
CREATE INDEX idx_appointments_doctor_window ON appointments(doctor_id, start_time, end_time);
CREATE INDEX idx_appointments_room_window ON appointments(room_id, start_time, end_time);
CREATE INDEX idx_appointments_status ON appointments(status);
CREATE INDEX idx_appointment_audit_appointment_id ON appointment_audit_log(appointment_id);
CREATE INDEX idx_billing_payment_status ON billing_ledger(payment_status);