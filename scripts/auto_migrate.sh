#!/bin/bash
set -e

echo "============================================================"
echo "  AUTOMATIC MIGRATION EXECUTION"
echo "============================================================"
echo ""

cd /opt/oracle/scripts/setup || exit 1

echo "Scripts found in /opt/oracle/scripts/setup:"
ls -lh *.sql 2>/dev/null || echo "No SQL files found!"
echo ""

# Execute each migration in order
for script in 001_*.sql 002_*.sql 003_*.sql 004_*.sql 005_*.sql 006_*.sql; do
    if [ ! -f "$script" ]; then
        echo "⚠ Skipping $script (not found)"
        continue
    fi
    
    echo "============================================================"
    echo "Running: $script"
    echo "============================================================"
    
    # Special handling for 006 seed data - allow partial success
    if [[ "$script" == 006_*.sql ]]; then
        echo "  ℹ Running seed data migration (errors will be ignored, successful inserts will be committed)"
        sqlplus -s my_user/abacate123@XEPDB1 @"$script" < /dev/null || true
        echo "  ✓ Complete: $script (with possible warnings)"
        echo ""
    else
        # Execute with sqlplus - strict mode for schema migrations
        if sqlplus -s my_user/abacate123@XEPDB1 @"$script" < /dev/null; then
            echo "  ✓ Complete: $script"
            echo ""
        else
            echo "  ✗ FAILED: $script"
            exit 1
        fi
    fi
done

# Deploy PL/SQL objects if script exists
if [ -f "/opt/oracle/deploy_plsql.sh" ]; then
    echo "============================================================"
    echo "Deploying PL/SQL Objects..."
    echo "============================================================"
    bash /opt/oracle/deploy_plsql.sh || echo "⚠ Some PL/SQL objects failed to deploy"
    echo ""
fi

echo "============================================================"
echo "  VERIFICATION"
echo "============================================================"
echo ""

sqlplus -s my_user/abacate123@XEPDB1 <<EOF
SET PAGESIZE 50
SET FEEDBACK OFF
SET HEADING ON

PROMPT Table Count:
SELECT COUNT(*) as "Total Tables" FROM user_tables;

PROMPT
PROMPT Constraint Summary:
SELECT 
    CASE constraint_type 
        WHEN 'P' THEN 'Primary Keys'
        WHEN 'R' THEN 'Foreign Keys'
        WHEN 'U' THEN 'Unique Keys'
        WHEN 'C' THEN 'Check Constraints'
    END as "Type",
    COUNT(*) as "Count"
FROM user_constraints 
GROUP BY constraint_type
ORDER BY constraint_type;

PROMPT
PROMPT Index Count:
SELECT COUNT(*) as "Total Indexes" FROM user_indexes;

PROMPT
PROMPT PL/SQL Objects Summary:
SELECT 
    object_type as "Type",
    COUNT(*) as "Count",
    SUM(CASE WHEN status = 'VALID' THEN 1 ELSE 0 END) as "Valid",
    SUM(CASE WHEN status = 'INVALID' THEN 1 ELSE 0 END) as "Invalid"
FROM user_objects 
WHERE object_type IN ('FUNCTION', 'PROCEDURE', 'PACKAGE', 'PACKAGE BODY', 'TRIGGER')
GROUP BY object_type
ORDER BY object_type;

EXIT;
EOF

echo ""
echo "============================================================"
echo "  ✓ MIGRATION COMPLETE"
echo "============================================================"
echo ""
