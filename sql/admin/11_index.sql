ALTER TABLE visit_history DROP INDEX tenant_id_idx;
ALTER TABLE visit_history ADD INDEX idx_tenant_id_competition_id(`tenant_id`, `competition_id`);