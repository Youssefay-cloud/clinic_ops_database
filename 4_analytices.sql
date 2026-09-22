
USE clinic_db;


-- Query 1: Doctor Utilization & Performance Scorecard
-- Evaluates total scheduled hours vs completed hours and total revenue produced.

SELECT 
    d.id AS doctor_id,
    d.full_name AS doctor_name,
    d.specialty,
    COUNT(a.id) AS total_appointments_booked,
    SUM(CASE WHEN a.status = 'completed' THEN 1 ELSE 0 END) AS completed_visits,
    SUM(CASE WHEN a.status = 'no_show' THEN 1 ELSE 0 END) AS no_shows,
    SUM(CASE WHEN a.status = 'cancelled' THEN 1 ELSE 0 END) AS cancellations,
    ROUND(
        100.0 * SUM(CASE WHEN a.status = 'completed' THEN 1 ELSE 0 END) / COUNT(a.id), 
        2
    ) AS completion_rate_pct,
    -- Each completed slot represents 0.5 hours (30 mins)
    ROUND(SUM(CASE WHEN a.status = 'completed' THEN 0.5 ELSE 0 END), 1) AS billable_clinical_hours,
    COALESCE(SUM(bl.total_amount), 0.00) AS total_gross_billed,
    COALESCE(SUM(bl.doctor_commission), 0.00) AS total_doctor_commission
FROM doctors d
LEFT JOIN appointments a ON d.id = a.doctor_id
LEFT JOIN billing_ledger bl ON a.id = bl.appointment_id
GROUP BY d.id, d.full_name, d.specialty
ORDER BY total_gross_billed DESC;


-- Query 2: Monthly Financial Reconciliation & Margin Breakdown
-- Tracks monthly cash collected, insurance receivables, and net profit margins.

SELECT 
    DATE_FORMAT(a.start_time, '%Y-%m') AS billing_month,
    COUNT(DISTINCT a.id) AS total_billed_appointments,
    SUM(bl.total_amount) AS gross_revenue,
    SUM(bl.patient_paid) AS patient_copays_collected,
    SUM(bl.insurance_paid) AS insurance_claims_billed,
    SUM(bl.clinic_cut) AS net_clinic_overhead_retained,
    SUM(bl.doctor_commission) AS doctor_payouts_due,
    ROUND(100.0 * SUM(bl.clinic_cut) / SUM(bl.total_amount), 2) AS clinic_profit_margin_pct
FROM appointments a
JOIN billing_ledger bl ON a.id = bl.appointment_id
WHERE a.status IN ('completed', 'no_show')
GROUP BY DATE_FORMAT(a.start_time, '%Y-%m')
ORDER BY billing_month DESC;


-- Query 3: Attendance Risk by Day of Week & Branch
-- Pinpoints high-risk operational days where front-desk confirmation calls are needed.

SELECT 
    b.name AS branch_name,
    DAYNAME(a.start_time) AS day_of_week,
    COUNT(a.id) AS total_scheduled,
    SUM(CASE WHEN a.status = 'no_show' THEN 1 ELSE 0 END) AS no_shows,
    SUM(CASE WHEN a.status = 'cancelled' THEN 1 ELSE 0 END) AS cancellations,
    ROUND(
        100.0 * (
            SUM(CASE WHEN a.status = 'no_show' THEN 1 ELSE 0 END) + 
            SUM(CASE WHEN a.status = 'cancelled' THEN 1 ELSE 0 END)
        ) / COUNT(a.id), 
        2
    ) AS non_attendance_rate_pct
FROM appointments a
JOIN rooms r ON a.room_id = r.id
JOIN branches b ON r.branch_id = b.id
GROUP BY b.name, DAYNAME(a.start_time), DAYOFWEEK(a.start_time)
ORDER BY b.name, DAYOFWEEK(a.start_time);