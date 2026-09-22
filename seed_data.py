import datetime
import random
from decimal import Decimal
from faker import Faker
import mysql.connector

# Initialize Faker
fake = Faker()

# Database Connection Config - Adjust credentials as needed
DB_CONFIG = {
    "host": "localhost",
    "user": "root",
    "password": "yoyo",  # <-- Replace with your MySQL password
    "database": "clinic_ops_db",
    "port": 3306,
}


def get_connection():
    return mysql.connector.connect(**DB_CONFIG)


def seed_database():
    conn = get_connection()
    cursor = conn.cursor()

    print("[*] Starting database population...")

    # ---------------------------------------------------------
    # 0. Clean previous records to avoid duplicate key errors
    # ---------------------------------------------------------
    print(" -> Cleaning previous records...")
    cursor.execute("SET FOREIGN_KEY_CHECKS = 0;")
    tables = [
        "billing_ledger", "appointment_audit_log", "appointment_services",
        "appointments", "services", "patients", "doctor_schedules",
        "doctors", "rooms", "branches"
    ]
    for table in tables:
        cursor.execute(f"TRUNCATE TABLE {table};")
    cursor.execute("SET FOREIGN_KEY_CHECKS = 1;")
    conn.commit()

    # ---------------------------------------------------------
    # 1. Seed Branches (3 Locations)
    # ---------------------------------------------------------
    print(" -> Seeding branches...")
    branches_data = [
        ("Downtown Medical Center", "12 Main St, City Center", "+201001112233", "Africa/Cairo"),
        ("Westside Specialty Clinic", "45 West Ave, Medical District", "+201004445566", "Africa/Cairo"),
        ("East Coast Polyclinic", "78 Corniche Rd, Coastal Zone", "+201007778899", "Africa/Cairo"),
    ]
    cursor.executemany(
        "INSERT INTO branches (name, address, phone, timezone) VALUES (%s, %s, %s, %s)",
        branches_data,
    )
    conn.commit()

    cursor.execute("SELECT id FROM branches ORDER BY id ASC")
    branch_ids = [row[0] for row in cursor.fetchall()]

    # ---------------------------------------------------------
    # 2. Seed Rooms (4 rooms per branch = 12 total)
    # ---------------------------------------------------------
    print(" -> Seeding rooms...")
    rooms_data = []
    room_types = ["general_exam", "ultrasound", "cardio_lab", "pediatrics"]
    for b_id in branch_ids:
        for idx in range(1, 5):
            rooms_data.append((b_id, f"Suite {b_id}0{idx}", room_types[idx - 1]))

    cursor.executemany(
        "INSERT INTO rooms (branch_id, room_number, room_type) VALUES (%s, %s, %s)",
        rooms_data,
    )
    conn.commit()

    cursor.execute("SELECT id, branch_id FROM rooms ORDER BY id ASC")
    room_pool = cursor.fetchall()  # [(room_id, branch_id), ...]

    # ---------------------------------------------------------
    # 3. Seed Doctors (12 Doctors - matches available rooms 1:1)
    # ---------------------------------------------------------
    print(" -> Seeding doctors...")
    specialties = [
        "Cardiology", "Dermatology", "Pediatrics", "Orthopedics",
        "Neurology", "Ophthalmology", "Internal Medicine"
    ]
    doctors_data = []
    for i in range(len(room_pool)):  # 12 doctors for 12 rooms
        doctors_data.append((
            f"Dr. {fake.first_name()} {fake.last_name()}",
            f"DOC-LIC-{1000 + i}",
            random.choice(specialties),
            Decimal(str(random.choice([0.15, 0.20, 0.25, 0.30]))),
            True,
        ))

    cursor.executemany(
        "INSERT INTO doctors (full_name, license_number, specialty, commission_rate, is_active) VALUES (%s, %s, %s, %s, %s)",
        doctors_data,
    )
    conn.commit()

    cursor.execute("SELECT id, commission_rate FROM doctors ORDER BY id ASC")
    doctor_rows = cursor.fetchall()
    doctor_ids = [d[0] for d in doctor_rows]
    doctor_commission_map = {d[0]: d[1] for d in doctor_rows}

    # ---------------------------------------------------------
    # 4. Seed Doctor Schedules
    # ---------------------------------------------------------
    print(" -> Seeding doctor schedules...")
    schedules_data = []
    # Deterministic room and branch assignment per doctor
    doctor_room_map = {}
    for idx, d_id in enumerate(doctor_ids):
        assigned_room = room_pool[idx]
        doctor_room_map[d_id] = assigned_room[0]
        assigned_branch = assigned_room[1]

        for day in range(1, 6):  # Monday through Friday
            schedules_data.append((
                d_id,
                assigned_branch,
                day,
                datetime.time(9, 0),
                datetime.time(17, 0),
            ))

    cursor.executemany(
        "INSERT INTO doctor_schedules (doctor_id, branch_id, day_of_week, shift_start, shift_end) VALUES (%s, %s, %s, %s, %s)",
        schedules_data,
    )
    conn.commit()

    # ---------------------------------------------------------
    # 5. Seed Services Catalog
    # ---------------------------------------------------------
    print(" -> Seeding services...")
    services_list = [
        ("SRV-CONS", "General Consultation", Decimal("250.00")),
        ("SRV-ECG", "Electrocardiogram (ECG)", Decimal("500.00")),
        ("SRV-ECHO", "Echocardiogram", Decimal("1200.00")),
        ("SRV-USND", "Abdominal Ultrasound", Decimal("750.00")),
        ("SRV-DERM", "Skin Biopsy & Analysis", Decimal("600.00")),
        ("SRV-XRAY", "Standard Radiography", Decimal("400.00")),
        ("SRV-LABS", "Comprehensive Blood Panel", Decimal("350.00")),
    ]
    cursor.executemany(
        "INSERT INTO services (service_code, description, standard_fee) VALUES (%s, %s, %s)",
        services_list,
    )
    conn.commit()

    cursor.execute("SELECT id, standard_fee FROM services ORDER BY id ASC")
    services_pool = cursor.fetchall()

    # ---------------------------------------------------------
    # 6. Seed Patients (5,000 Patients)
    # ---------------------------------------------------------
    print(" -> Seeding 5,000 patients...")
    patients_data = []
    for i in range(1, 5001):
        patients_data.append((
            f"MRN-{i:06d}",
            fake.name(),
            fake.date_of_birth(minimum_age=1, maximum_age=85),
            fake.phone_number()[:30],
            fake.name()[:150],
        ))

    cursor.executemany(
        "INSERT INTO patients (mrn, full_name, date_of_birth, phone, emergency_contact) VALUES (%s, %s, %s, %s, %s)",
        patients_data,
    )
    conn.commit()

    cursor.execute("SELECT id FROM patients ORDER BY id ASC")
    patient_ids = [p[0] for p in cursor.fetchall()]

    # ---------------------------------------------------------
    # 7. Generate 50,000 Appointments (Collision-Free)
    # ---------------------------------------------------------
    print(" -> Generating and inserting 50,000 appointments (in batches)...")
    start_anchor = datetime.datetime.now() - datetime.timedelta(days=300)
    start_anchor = start_anchor.replace(hour=9, minute=0, second=0, microsecond=0)

    total_needed = 50000
    appointment_rows = []
    status_weights = ["completed"] * 75 + ["cancelled"] * 12 + ["no_show"] * 8 + ["confirmed"] * 5

    current_count = 0
    day_offset = 0

    while current_count < total_needed:
        current_date = start_anchor + datetime.timedelta(days=day_offset)
        # Skip weekends (Saturday=5, Sunday=6)
        if current_date.weekday() in (5, 6):
            day_offset += 1
            continue

        for slot in range(16):  # 16 slots of 30 mins: 09:00 -> 17:00
            slot_start = current_date + datetime.timedelta(minutes=30 * slot)
            slot_end = slot_start + datetime.timedelta(minutes=30)

            for d_id in doctor_ids:
                if current_count >= total_needed:
                    break

                assigned_room_id = doctor_room_map[d_id]
                app_status = random.choice(status_weights)
                cancel_reason = fake.sentence(nb_words=6) if app_status == "cancelled" else None

                appointment_rows.append((
                    random.choice(patient_ids),
                    d_id,
                    assigned_room_id,
                    slot_start.strftime("%Y-%m-%d %H:%M:%S"),
                    slot_end.strftime("%Y-%m-%d %H:%M:%S"),
                    app_status,
                    cancel_reason,
                ))
                current_count += 1

            if current_count >= total_needed:
                break

        day_offset += 1

    # Batch insert appointments (chunks of 2,000)
    insert_app_query = """
        INSERT INTO appointments 
        (patient_id, doctor_id, room_id, start_time, end_time, status, cancellation_reason)
        VALUES (%s, %s, %s, %s, %s, %s, %s)
    """
    for i in range(0, len(appointment_rows), 2000):
        batch = appointment_rows[i:i + 2000]
        cursor.executemany(insert_app_query, batch)
        conn.commit()
        print(f"    ... {min(i + 2000, len(appointment_rows))} / {len(appointment_rows)} appointments inserted")

    # Fetch inserted appointments for downstream tables
    cursor.execute("SELECT id, doctor_id, status FROM appointments ORDER BY id ASC")
    all_appointments = cursor.fetchall()

    # ---------------------------------------------------------
    # 8. Seed Appointment Services & Billing Ledger
    # ---------------------------------------------------------
    print(" -> Generating appointment services and billing ledger entries...")

    app_services_rows = []
    billing_rows = []

    for app_id, doc_id, status in all_appointments:
        selected_services = random.sample(services_pool, k=random.choice([1, 2]))
        total_appt_fee = Decimal("0.00")

        for s_id, s_fee in selected_services:
            app_services_rows.append((app_id, s_id, s_fee))
            total_appt_fee += s_fee

        if status in ("completed", "confirmed", "no_show"):
            comm_rate = doctor_commission_map[doc_id]
            doc_payout = (total_appt_fee * comm_rate).quantize(Decimal("0.01"))
            clinic_cut = total_appt_fee - doc_payout

            if status == "completed":
                patient_paid = (total_appt_fee * Decimal("0.30")).quantize(Decimal("0.01"))
                insurance_paid = total_appt_fee - patient_paid
                p_status = "paid"
                settled_at = fake.date_time_between(start_date="-300d", end_date="now")
            elif status == "no_show":
                total_appt_fee = Decimal("150.00")
                doc_payout = Decimal("0.00")
                clinic_cut = total_appt_fee
                patient_paid = Decimal("0.00")
                insurance_paid = Decimal("0.00")
                p_status = "unpaid"
                settled_at = None
            else:
                patient_paid = Decimal("0.00")
                insurance_paid = Decimal("0.00")
                p_status = "unpaid"
                settled_at = None

            billing_rows.append((
                app_id,
                total_appt_fee,
                patient_paid,
                insurance_paid,
                clinic_cut,
                doc_payout,
                p_status,
                settled_at,
            ))

    # Insert appointment services in batches
    insert_as_query = "INSERT INTO appointment_services (appointment_id, service_id, billed_fee) VALUES (%s, %s, %s)"
    for i in range(0, len(app_services_rows), 5000):
        cursor.executemany(insert_as_query, app_services_rows[i:i + 5000])
        conn.commit()

    # Insert billing ledger in batches
    insert_bill_query = """
        INSERT INTO billing_ledger 
        (appointment_id, total_amount, patient_paid, insurance_paid, clinic_cut, doctor_commission, payment_status, settled_at)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
    """
    for i in range(0, len(billing_rows), 5000):
        cursor.executemany(insert_bill_query, billing_rows[i:i + 5000])
        conn.commit()

    print("[+] Database seeding complete! Summary:")
    print(f"    - Patients: {len(patient_ids)}")
    print(f"    - Appointments: {len(all_appointments)}")
    print(f"    - Services Rendered: {len(app_services_rows)}")
    print(f"    - Billing Ledger Records: {len(billing_rows)}")

    cursor.close()
    conn.close()


if __name__ == "__main__":
    seed_database()