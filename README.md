# Question 2: University Fee Payments

PostgreSQL. Run `solution.sql` from top to bottom. It creates its own schema `q2`.
Scheduled jobs use pg_cron.

## Index
`payments(student_id, paid_on)`

Payments are filtered by one student (equality) and a paid_on range. With student_id first, all of a student's payments sit together in the index, sorted by date, so the range is one contiguous scan. The same index also speeds up the balance calculation.
