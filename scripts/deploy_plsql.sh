#!/bin/bash
# Don't use set -e as it causes issues with arithmetic expressions

echo "============================================================"
echo "  PL/SQL OBJECTS DEPLOYMENT"
echo "============================================================"
echo ""

PLSQL_DIR="/opt/oracle/plsql"

if [ ! -d "$PLSQL_DIR" ]; then
    echo "ERROR: PL/SQL directory not found: $PLSQL_DIR"
    exit 1
fi

cd "$PLSQL_DIR" || exit 1

echo "DEBUG: Current directory: $(pwd)"
echo "DEBUG: Directory contents:"
ls -la
echo ""

# Function to compile a single file
compile_file() {
    local sql_file="$1"
    local filename=$(basename "$sql_file")
    local file_content=$(cat "$sql_file")
    local first_line=$(head -1 "$sql_file")
    local first_word=$(echo "$first_line" | awk '{print toupper($1)}')
    
    # Build SQL - add CREATE OR REPLACE if needed
    if [ "$first_word" = "CREATE" ]; then
        sql_to_run="SET DEFINE OFF;
$file_content"
    else
        sql_to_run="SET DEFINE OFF;
CREATE OR REPLACE $file_content"
    fi
    
    # Execute and check result
    output=$(echo "$sql_to_run" | sqlplus -s my_user/abacate123@XEPDB1 2>&1)
    
    if echo "$output" | grep -qi "error\|ORA-"; then
        echo "  ⚠ Failed: $filename"
        echo "    $(echo "$output" | grep -i "error\|ORA-" | head -1)"
        return 1
    else
        echo "  ✓ Created: $filename"
        return 0
    fi
}

total_success=0
total_failed=0

# 1. Deploy Package Specifications (from package/ directory)
if [ -d "package" ]; then
    echo "============================================================"
    echo "Deploying Package Specifications..."
    echo "============================================================"
    for sql_file in package/*.sql; do
        [ -f "$sql_file" ] || continue
        # Check if it's actually a spec (not a body)
        first_line=$(head -1 "$sql_file")
        if echo "$first_line" | grep -qi "package body"; then
            echo "  Skipping body in package dir: $(basename $sql_file)"
            continue
        fi
        if compile_file "$sql_file"; then
            total_success=$((total_success + 1))
        else
            total_failed=$((total_failed + 1))
        fi
    done
    echo ""
fi

# 2. Deploy Package Bodies (from package_body/ directory)
if [ -d "package_body" ]; then
    echo "============================================================"
    echo "Deploying Package Bodies..."
    echo "============================================================"
    for sql_file in package_body/*.sql; do
        [ -f "$sql_file" ] || continue
        if compile_file "$sql_file"; then
            total_success=$((total_success + 1))
        else
            total_failed=$((total_failed + 1))
        fi
    done
    echo ""
fi

# 3. Deploy Functions
if [ -d "function" ]; then
    echo "============================================================"
    echo "Deploying Functions..."
    echo "============================================================"
    for sql_file in function/*.sql; do
        [ -f "$sql_file" ] || continue
        if compile_file "$sql_file"; then
            total_success=$((total_success + 1))
        else
            total_failed=$((total_failed + 1))
        fi
    done
    echo ""
fi

# 4. Deploy Procedures
if [ -d "procedure" ]; then
    echo "============================================================"
    echo "Deploying Procedures..."
    echo "============================================================"
    for sql_file in procedure/*.sql; do
        [ -f "$sql_file" ] || continue
        if compile_file "$sql_file"; then
            total_success=$((total_success + 1))
        else
            total_failed=$((total_failed + 1))
        fi
    done
    echo ""
fi

# 5. Deploy Triggers
if [ -d "trigger" ]; then
    echo "============================================================"
    echo "Deploying Triggers..."
    echo "============================================================"
    for sql_file in trigger/*.sql; do
        [ -f "$sql_file" ] || continue
        if compile_file "$sql_file"; then
            total_success=$((total_success + 1))
        else
            total_failed=$((total_failed + 1))
        fi
    done
    echo ""
fi

echo "============================================================"
echo "Summary: $total_success successful, $total_failed failed"
echo "============================================================"
echo ""

# Recompile invalid objects
echo "============================================================"
echo "Recompiling invalid objects..."
echo "============================================================"

sqlplus -s my_user/abacate123@XEPDB1 <<EOF
SET SERVEROUTPUT ON;
BEGIN
    DBMS_UTILITY.COMPILE_SCHEMA(schema => 'MY_USER', compile_all => FALSE);
END;
/
EXIT;
EOF

echo "  ✓ Recompilation complete"
echo ""

echo "============================================================"
echo "  PL/SQL DEPLOYMENT COMPLETE"
echo "============================================================"