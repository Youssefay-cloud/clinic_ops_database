-- ============================================================================
-- CLINIC APPOINTMENT LEDGER - TRIGGERS FOR MYSQL
-- ============================================================================

DELIMITER $$

-- ----------------------------------------------------------------------------
-- 1. ANTI-OVERLAP VALIDATION (BEFORE INSERT)
-- ----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_prevent_double_booking_insert$$
CREATE TRIGGER trg_prevent_double_booking_insert
BEFORE INSERT ON appointments
FOR EACH ROW
BEGIN
    DECLARE doctor_conflicts INT DEFAULT 0;
    DECLARE room_conflicts INT DEFAULT 0;

    -- Only check active appointments
    IF NEW.status NOT IN ('cancelled', 'no_show') THEN
        
        -- Check doctor schedule collision: (StartA < EndB) AND (EndA > StartB)
        SELECT COUNT(*) INTO doctor_conflicts
        FROM appointments
        WHERE doctor_id = NEW.doctor_id
          AND status NOT IN ('cancelled', 'no_show')
          AND NEW.start_time < end_time
          AND NEW.end_time > start_time;

        IF doctor_conflicts > 0 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Double-Booking Error: Doctor already has an active appointment during this time window.';
        END IF;

        -- Check room schedule collision
        SELECT COUNT(*) INTO room_conflicts
        FROM appointments
        WHERE room_id = NEW.room_id
          AND status NOT IN ('cancelled', 'no_show')
          AND NEW.start_time < end_time
          AND NEW.end_time > start_time;

        IF room_conflicts > 0 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Room Collision Error: Physical room is already occupied during this time window.';
        END IF;

    END IF;
END$$

-- ----------------------------------------------------------------------------
-- 2. ANTI-OVERLAP VALIDATION (BEFORE UPDATE)
-- ----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_prevent_double_booking_update$$
CREATE TRIGGER trg_prevent_double_booking_update
BEFORE UPDATE ON appointments
FOR EACH ROW
BEGIN
    DECLARE doctor_conflicts INT DEFAULT 0;
    DECLARE room_conflicts INT DEFAULT 0;

    -- Only check active appointments
    IF NEW.status NOT IN ('cancelled', 'no_show') THEN
        
        -- Exclude the current updating record itself (id <> NEW.id)
        SELECT COUNT(*) INTO doctor_conflicts
        FROM appointments
        WHERE doctor_id = NEW.doctor_id
          AND id <> NEW.id
          AND status NOT IN ('cancelled', 'no_show')
          AND NEW.start_time < end_time
          AND NEW.end_time > start_time;

        IF doctor_conflicts > 0 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Double-Booking Error: Doctor already has an active appointment during this time window.';
        END IF;

        -- Check room collision
        SELECT COUNT(*) INTO room_conflicts
        FROM appointments
        WHERE room_id = NEW.room_id
          AND id <> NEW.id
          AND status NOT IN ('cancelled', 'no_show')
          AND NEW.start_time < end_time
          AND NEW.end_time > start_time;

        IF room_conflicts > 0 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Room Collision Error: Physical room is already occupied during this time window.';
        END IF;

    END IF;
END$$

-- ----------------------------------------------------------------------------
-- 3. AUDIT LOGGING (AFTER INSERT)
-- ----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_audit_appointments_insert$$
CREATE TRIGGER trg_audit_appointments_insert
AFTER INSERT ON appointments
FOR EACH ROW
BEGIN
    INSERT INTO appointment_audit_log (
        appointment_id,
        changed_by_user,
        action_type,
        old_status,
        new_status,
        previous_start_time,
        new_start_time,
        previous_room_id,
        new_room_id,
        changed_at
    ) VALUES (
        NEW.id,
        CURRENT_USER(),
        'INSERT',
        NULL,
        NEW.status,
        NULL,
        NEW.start_time,
        NULL,
        NEW.room_id,
        CURRENT_TIMESTAMP
    );
END$$

-- ----------------------------------------------------------------------------
-- 4. AUDIT LOGGING (AFTER UPDATE)
-- ----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_audit_appointments_update$$
CREATE TRIGGER trg_audit_appointments_update
AFTER UPDATE ON appointments
FOR EACH ROW
BEGIN
    -- Log only if critical operational columns changed
    IF (OLD.status <> NEW.status) OR 
       (OLD.start_time <> NEW.start_time) OR 
       (OLD.end_time <> NEW.end_time) OR 
       (OLD.room_id <> NEW.room_id) THEN

        INSERT INTO appointment_audit_log (
            appointment_id,
            changed_by_user,
            action_type,
            old_status,
            new_status,
            previous_start_time,
            new_start_time,
            previous_room_id,
            new_room_id,
            changed_at
        ) VALUES (
            NEW.id,
            CURRENT_USER(),
            IF(NEW.status = 'cancelled', 'CANCEL', 'UPDATE'),
            OLD.status,
            NEW.status,
            OLD.start_time,
            NEW.start_time,
            OLD.room_id,
            NEW.room_id,
            CURRENT_TIMESTAMP
        );
    END IF;
END$$

DELIMITER ;