-- =========================================
-- PayScope Project
-- File: 01_create_schemas.sql
-- Purpose: Create layered schemas for the project
-- =========================================

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS clean;
CREATE SCHEMA IF NOT EXISTS mart;