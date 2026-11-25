DROP SCHEMA IF EXISTS q2 CASCADE; CREATE SCHEMA q2; SET search_path TO q2;

CREATE TABLE students (
  student_id SERIAL PRIMARY KEY, student_number VARCHAR(20) NOT NULL UNIQUE,
  full_name VARCHAR(100) NOT NULL, fee_due NUMERIC(12,2) NOT NULL CHECK (fee_due >= 0));
CREATE TABLE payments (
  payment_id SERIAL PRIMARY KEY, student_id INT NOT NULL REFERENCES students,
  amount NUMERIC(12,2) NOT NULL CHECK (amount > 0), paid_on DATE NOT NULL DEFAULT CURRENT_DATE);
CREATE TABLE payment_audit (
  audit_id SERIAL PRIMARY KEY, payment_id INT NOT NULL REFERENCES payments,
  student_id INT NOT NULL REFERENCES students, amount NUMERIC(12,2) NOT NULL,
  logged_at TIMESTAMP NOT NULL DEFAULT now());
CREATE TABLE daily_collections (
  collection_date DATE PRIMARY KEY, payment_count INT NOT NULL, total_amount NUMERIC(12,2) NOT NULL);

CREATE FUNCTION fn_fee_balance(p_student_id INT) RETURNS NUMERIC AS $$
DECLARE v NUMERIC;
BEGIN
  SELECT fee_due INTO v FROM students WHERE student_id = p_student_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Unknown student %', p_student_id; END IF;
  RETURN v - COALESCE((SELECT SUM(amount) FROM payments WHERE student_id = p_student_id), 0);
END $$ LANGUAGE plpgsql STABLE;

CREATE PROCEDURE pr_receive_payment(p_student_id INT, p_amount NUMERIC, p_paid_on DATE)
LANGUAGE plpgsql AS $$
DECLARE v_bal NUMERIC;
BEGIN
  IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'Amount must be positive'; END IF;
  PERFORM 1 FROM students WHERE student_id = p_student_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Unknown student %', p_student_id; END IF;
  v_bal := fn_fee_balance(p_student_id);
  IF p_amount > v_bal THEN RAISE EXCEPTION 'Payment % exceeds balance %', p_amount, v_bal; END IF;
  INSERT INTO payments(student_id, amount, paid_on) VALUES (p_student_id, p_amount, COALESCE(p_paid_on, CURRENT_DATE));
END $$;

CREATE FUNCTION trg_fn_payment_audit() RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO payment_audit(payment_id, student_id, amount, logged_at)
  VALUES (NEW.payment_id, NEW.student_id, NEW.amount, now());
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_payment_audit AFTER INSERT ON payments
FOR EACH ROW EXECUTE FUNCTION trg_fn_payment_audit();

CREATE PROCEDURE pr_refresh_collections(p_day DATE) LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO daily_collections
  SELECT p_day, COUNT(*), COALESCE(SUM(amount),0) FROM payments WHERE paid_on = p_day
  ON CONFLICT (collection_date) DO UPDATE
    SET payment_count = EXCLUDED.payment_count, total_amount = EXCLUDED.total_amount;
END $$;

INSERT INTO students(student_number, full_name, fee_due) VALUES
 ('2024001','Mwansa Banda',5000), ('2024002','Chipo Phiri',3000), ('2024003','Joseph Mumba',2000);
CALL pr_receive_payment(1,1000,CURRENT_DATE-1); CALL pr_receive_payment(1,1500,CURRENT_DATE-1);
CALL pr_receive_payment(1,500,CURRENT_DATE);    CALL pr_receive_payment(2,1000,CURRENT_DATE-1);
CALL pr_receive_payment(2,1000,CURRENT_DATE);   CALL pr_receive_payment(2,500,CURRENT_DATE);

CREATE VIEW v_fee_balances AS
SELECT s.student_number, s.full_name, s.fee_due - COALESCE(SUM(p.amount),0) AS outstanding_balance
  FROM students s LEFT JOIN payments p ON p.student_id = s.student_id
 GROUP BY s.student_id, s.student_number, s.full_name, s.fee_due
HAVING s.fee_due - COALESCE(SUM(p.amount),0) > 0;

CREATE INDEX idx_pay_student_date ON payments(student_id, paid_on);
EXPLAIN SELECT * FROM payments WHERE student_id = 1 AND paid_on BETWEEN CURRENT_DATE-7 AND CURRENT_DATE;

SELECT cron.schedule('q2_refresh_collections', '0 1 * * *',
  $$SET search_path TO q2; CALL pr_refresh_collections(CURRENT_DATE - 1)$$);
