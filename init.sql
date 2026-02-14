-- PostgreSQL extensions for Vision UI MCP Server
--
-- Tables are created at runtime by the Python pipeline and CocoIndex.
-- This file only enables required extensions.

CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
