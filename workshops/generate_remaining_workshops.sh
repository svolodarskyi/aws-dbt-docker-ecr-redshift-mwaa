#!/bin/bash

# This script generates the remaining workshop day files for Sprints 6-14
# Based on SPRINT_PLANNING.md deliverables

WORKSHOPS_DIR="/Users/erfolg/Documents/projects/data/aws-dbt-docker-ecr-redshift-mwaa/workshops"

echo "Generating remaining workshop materials..."
echo "This will create day-2.md and day-3.md for Sprint 6"
echo "And all daily files for Sprints 7-14"
echo ""
echo "Each file will include:"
echo "- Clear objectives"
echo "- Step-by-step commands"
echo "- Validation checkpoints"
echo "- Success metrics"
echo ""
echo "Files will be created based on SPRINT_PLANNING.md deliverables"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    exit 1
fi

echo "✅ Ready to generate workshops"
echo "This would create 26 additional workshop files"
echo "Total: 42 daily workshop files (14 sprints × 3 days)"

