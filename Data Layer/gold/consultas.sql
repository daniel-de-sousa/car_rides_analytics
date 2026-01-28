-- ============================================================================
-- GOLD LAYER: CONSULTAS ANALÍTICAS
-- Queries para análise das Corridas da Uber e Ola
-- ============================================================================

-- ============================================================================
-- CONSULTA 1: Top Rotas Mais Frequentes com Viagens Bem-Sucedidas
-- ============================================================================
-- Objetivo: Identificar as rotas com maior volume de viagens concluídas
-- ----------------------------------------------------------------------------

WITH rotas_sucesso AS (
    SELECT 
        f.rot_srk,
        r.pck_loc,
        r.drp_loc,
        COUNT(*) AS total_viagens,
        AVG(f.bkg_val) AS valor_medio,
        AVG(f.rid_dst) AS distancia_media
    FROM dw.car_trp f
    INNER JOIN dw.dim_rot r ON f.rot_srk = r.rot_key
    INNER JOIN dw.dim_sts s ON f.sts_srk = s.sts_key
    WHERE s.bkg_sts = 'Success'
    GROUP BY f.rot_srk, r.pck_loc, r.drp_loc
)
SELECT 
    pck_loc AS origem,
    drp_loc AS destino,
    total_viagens,
    ROUND(valor_medio, 2) AS valor_medio_viagem,
    ROUND(distancia_media, 2) AS distancia_media_km
FROM rotas_sucesso
ORDER BY total_viagens DESC;


-- ============================================================================
-- CONSULTA 2: Análise de Performance de Motoristas por Avaliação
-- ============================================================================
-- Objetivo: Comparar desempenho de motoristas agrupados por faixa de avaliação
-- ----------------------------------------------------------------------------

WITH motoristas_por_rating AS (
    SELECT 
        CASE 
            WHEN f.drv_rtg >= 4.5 THEN 'Excelente (≥4.5)'
            WHEN f.drv_rtg >= 4.0 THEN 'Bom (4.0-4.4)'
            WHEN f.drv_rtg >= 3.5 THEN 'Regular (3.5-3.9)'
            ELSE 'Abaixo da Média (<3.5)'
        END AS faixa_avaliacao,
        COUNT(*) AS total_corridas,
        COUNT(CASE WHEN s.bkg_sts = 'Success' THEN 1 END) AS corridas_concluidas,
        AVG(f.bkg_val) AS valor_medio,
        AVG(f.drv_tim_acp) AS tempo_medio_aceitacao
    FROM dw.car_trp f
    INNER JOIN dw.dim_sts s ON f.sts_srk = s.sts_key
    WHERE f.drv_rtg IS NOT NULL
    GROUP BY 
        CASE 
            WHEN f.drv_rtg >= 4.5 THEN 'Excelente (≥4.5)'
            WHEN f.drv_rtg >= 4.0 THEN 'Bom (4.0-4.4)'
            WHEN f.drv_rtg >= 3.5 THEN 'Regular (3.5-3.9)'
            ELSE 'Abaixo da Média (<3.5)'
        END
)
SELECT 
    faixa_avaliacao,
    total_corridas,
    corridas_concluidas,
    ROUND(100.0 * corridas_concluidas / NULLIF(total_corridas, 0), 2) AS taxa_sucesso_pct,
    ROUND(valor_medio, 2) AS ticket_medio,
    ROUND(tempo_medio_aceitacao / 60.0, 2) AS tempo_aceitacao_minutos
FROM motoristas_por_rating
ORDER BY 
    CASE faixa_avaliacao
        WHEN 'Excelente (≥4.5)' THEN 1
        WHEN 'Bom (4.0-4.4)' THEN 2
        WHEN 'Regular (3.5-3.9)' THEN 3
        ELSE 4
    END;


-- ============================================================================
-- CONSULTA 3: Performance por Tipo de Veículo e Método de Pagamento
-- ============================================================================
-- Objetivo: Avaliar qual combinação veículo-pagamento gera mais receita
-- ----------------------------------------------------------------------------

WITH performance_veiculo_pagamento AS (
    SELECT 
        v.vec_typ,
        p.pay_mtd,
        s.bkg_sts,
        COUNT(*) AS total_viagens,
        SUM(f.bkg_val) AS receita_total,
        AVG(f.bkg_val) AS ticket_medio,
        AVG(f.drv_rtg) AS avaliacao_media_motorista
    FROM dw.car_trp f
    INNER JOIN dw.dim_vec v ON f.vec_srk = v.vec_key
    INNER JOIN dw.dim_pay p ON f.pay_srk = p.pay_key
    INNER JOIN dw.dim_sts s ON f.sts_srk = s.sts_key
    WHERE s.bkg_sts = 'Success'
    GROUP BY v.vec_typ, p.pay_mtd, s.bkg_sts
)
SELECT 
    vec_typ AS tipo_veiculo,
    pay_mtd AS metodo_pagamento,
    total_viagens,
    ROUND(receita_total, 2) AS receita_total,
    ROUND(ticket_medio, 2) AS valor_medio,
    ROUND(avaliacao_media_motorista, 2) AS rating_motorista
FROM performance_veiculo_pagamento
ORDER BY receita_total DESC;


-- ============================================================================
-- CONSULTA 4: Análise Temporal - Horários de Pico de Demanda
-- ============================================================================
-- Objetivo: Identificar padrões de demanda por hora do dia
-- ----------------------------------------------------------------------------

WITH demanda_horaria AS (
    SELECT 
        EXTRACT(HOUR FROM t.tim) AS hora_dia,
        s.bkg_sts,
        COUNT(*) AS total_solicitacoes,
        COUNT(CASE WHEN s.bkg_sts = 'Success' THEN 1 END) AS viagens_concluidas,
        AVG(f.bkg_val) AS valor_medio,
        AVG(f.drv_tim_acp) AS tempo_medio_aceitacao
    FROM dw.car_trp f
    INNER JOIN dw.dim_tim t ON f.tim_srk = t.tim_key
    INNER JOIN dw.dim_sts s ON f.sts_srk = s.sts_key
    GROUP BY EXTRACT(HOUR FROM t.tim), s.bkg_sts
)
SELECT 
    hora_dia,
    total_solicitacoes,
    viagens_concluidas,
    ROUND(100.0 * viagens_concluidas / NULLIF(total_solicitacoes, 0), 2) AS taxa_conclusao_pct,
    ROUND(valor_medio, 2) AS valor_medio,
    ROUND(tempo_medio_aceitacao / 60.0, 2) AS tempo_aceitacao_minutos
FROM demanda_horaria
GROUP BY hora_dia, total_solicitacoes, viagens_concluidas, valor_medio, tempo_medio_aceitacao
ORDER BY hora_dia;


-- ============================================================================
-- CONSULTA 5: Análise de Padrões de Pagamento e Comportamento de Gasto
-- ============================================================================
-- Objetivo: Identificar correlação entre método de pagamento e padrões de consumo
-- ----------------------------------------------------------------------------

WITH analise_pagamento AS (
    SELECT 
        p.pay_mtd,
        t.dat,
        EXTRACT(HOUR FROM t.tim) AS hora,
        v.vec_typ,
        COUNT(*) AS total_transacoes,
        SUM(f.bkg_val) AS valor_total,
        AVG(f.bkg_val) AS ticket_medio,
        AVG(f.rid_dst) AS distancia_media,
        COUNT(CASE WHEN s.bkg_sts = 'Success' THEN 1 END) AS transacoes_sucesso
    FROM dw.car_trp f
    INNER JOIN dw.dim_pay p ON f.pay_srk = p.pay_key
    INNER JOIN dw.dim_tim t ON f.tim_srk = t.tim_key
    INNER JOIN dw.dim_vec v ON f.vec_srk = v.vec_key
    INNER JOIN dw.dim_sts s ON f.sts_srk = s.sts_key
    WHERE p.pay_mtd IS NOT NULL
    GROUP BY p.pay_mtd, t.dat, EXTRACT(HOUR FROM t.tim), v.vec_typ
),
metricas_por_metodo AS (
    SELECT 
        pay_mtd,
        CASE 
            WHEN hora BETWEEN 6 AND 11 THEN 'Manhã (6h-11h)'
            WHEN hora BETWEEN 12 AND 17 THEN 'Tarde (12h-17h)'
            WHEN hora BETWEEN 18 AND 23 THEN 'Noite (18h-23h)'
            ELSE 'Madrugada (0h-5h)'
        END AS periodo_dia,
        vec_typ,
        SUM(total_transacoes) AS total_uso,
        SUM(transacoes_sucesso) AS total_sucesso,
        AVG(ticket_medio) AS valor_medio,
        AVG(distancia_media) AS dist_media,
        SUM(valor_total) AS receita_total
    FROM analise_pagamento
    GROUP BY pay_mtd, 
        CASE 
            WHEN hora BETWEEN 6 AND 11 THEN 'Manhã (6h-11h)'
            WHEN hora BETWEEN 12 AND 17 THEN 'Tarde (12h-17h)'
            WHEN hora BETWEEN 18 AND 23 THEN 'Noite (18h-23h)'
            ELSE 'Madrugada (0h-5h)'
        END,
        vec_typ
)
SELECT 
    pay_mtd AS metodo_pagamento,
    periodo_dia,
    vec_typ AS tipo_veiculo,
    total_uso AS transacoes_totais,
    total_sucesso AS transacoes_concluidas,
    ROUND(100.0 * total_sucesso / NULLIF(total_uso, 0), 2) AS taxa_conclusao_pct,
    ROUND(valor_medio, 2) AS ticket_medio,
    ROUND(dist_media, 2) AS distancia_media_km,
    ROUND(receita_total, 2) AS receita_total,
    ROUND(receita_total / NULLIF(total_sucesso, 0), 2) AS receita_por_viagem
FROM metricas_por_metodo
WHERE total_uso >= 5
ORDER BY receita_total DESC;


-- ============================================================================
-- CONSULTA 6: Taxa de Conversão e Tempo de Resposta por Tipo de Veículo
-- ============================================================================
-- Objetivo: Avaliar performance operacional por categoria de veículo
-- ----------------------------------------------------------------------------

WITH metricas_veiculo AS (
    SELECT 
        v.vec_typ,
        COUNT(*) AS total_solicitacoes,
        COUNT(CASE WHEN s.bkg_sts = 'Success' THEN 1 END) AS viagens_sucesso,
        AVG(f.drv_tim_acp) AS tempo_medio_aceitacao,
        AVG(f.psg_tim_bdg) AS tempo_medio_embarque,
        AVG(f.bkg_val) AS valor_medio
    FROM dw.car_trp f
    INNER JOIN dw.dim_vec v ON f.vec_srk = v.vec_key
    INNER JOIN dw.dim_sts s ON f.sts_srk = s.sts_key
    GROUP BY v.vec_typ
)
SELECT 
    vec_typ AS tipo_veiculo,
    total_solicitacoes,
    viagens_sucesso,
    ROUND(100.0 * viagens_sucesso / NULLIF(total_solicitacoes, 0), 2) AS taxa_conversao_pct,
    ROUND(tempo_medio_aceitacao / 60.0, 2) AS tempo_aceitacao_min,
    ROUND(tempo_medio_embarque / 60.0, 2) AS tempo_embarque_min,
    ROUND((tempo_medio_aceitacao + tempo_medio_embarque) / 60.0, 2) AS tempo_total_espera_min,
    ROUND(valor_medio, 2) AS valor_medio
FROM metricas_veiculo
ORDER BY taxa_conversao_pct DESC;


-- ============================================================================
-- CONSULTA 7: Análise de Viagens Incompletas - Problemas Operacionais
-- ============================================================================
-- Objetivo: Identificar padrões em viagens iniciadas mas não concluídas
-- ----------------------------------------------------------------------------

WITH viagens_incompletas AS (
    SELECT 
        s.icm_rid,
        s.icm_rid_rsn AS motivo,
        v.vec_typ,
        r.pck_loc,
        r.drp_loc,
        COUNT(*) AS total_casos,
        AVG(f.rid_dst) AS distancia_media,
        AVG(f.bkg_val) AS valor_medio_perdido
    FROM dw.car_trp f
    INNER JOIN dw.dim_sts s ON f.sts_srk = s.sts_key
    INNER JOIN dw.dim_vec v ON f.vec_srk = v.vec_key
    INNER JOIN dw.dim_rot r ON f.rot_srk = r.rot_key
    WHERE s.icm_rid = TRUE
    GROUP BY s.icm_rid, s.icm_rid_rsn, v.vec_typ, r.pck_loc, r.drp_loc
)
SELECT 
    motivo AS motivo_nao_conclusao,
    vec_typ AS tipo_veiculo,
    pck_loc AS origem,
    drp_loc AS destino,
    total_casos,
    ROUND(distancia_media, 2) AS distancia_media_km,
    ROUND(valor_medio_perdido, 2) AS valor_medio_perdido
FROM viagens_incompletas
ORDER BY total_casos DESC;


-- ============================================================================
-- CONSULTA 8: Análise Semanal de Performance e Tendências
-- ============================================================================
-- Objetivo: Identificar padrões semanais de demanda e performance
-- ----------------------------------------------------------------------------

WITH performance_semanal AS (
    SELECT 
        EXTRACT(DOW FROM t.dat) AS dia_semana,
        CASE EXTRACT(DOW FROM t.dat)
            WHEN 0 THEN 'Domingo'
            WHEN 1 THEN 'Segunda'
            WHEN 2 THEN 'Terça'
            WHEN 3 THEN 'Quarta'
            WHEN 4 THEN 'Quinta'
            WHEN 5 THEN 'Sexta'
            WHEN 6 THEN 'Sábado'
        END AS nome_dia,
        COUNT(*) AS total_viagens,
        COUNT(CASE WHEN s.bkg_sts = 'Success' THEN 1 END) AS viagens_sucesso,
        SUM(CASE WHEN s.bkg_sts = 'Success' THEN f.bkg_val ELSE 0 END) AS receita_total,
        AVG(f.drv_rtg) AS avaliacao_media_motorista,
        AVG(f.rid_dst) AS distancia_media
    FROM dw.car_trp f
    INNER JOIN dw.dim_tim t ON f.tim_srk = t.tim_key
    INNER JOIN dw.dim_sts s ON f.sts_srk = s.sts_key
    GROUP BY EXTRACT(DOW FROM t.dat)
)
SELECT 
    nome_dia,
    total_viagens,
    viagens_sucesso,
    ROUND(100.0 * viagens_sucesso / NULLIF(total_viagens, 0), 2) AS taxa_sucesso_pct,
    ROUND(receita_total, 2) AS receita_total,
    ROUND(receita_total / NULLIF(viagens_sucesso, 0), 2) AS ticket_medio,
    ROUND(avaliacao_media_motorista, 2) AS rating_motorista,
    ROUND(distancia_media, 2) AS distancia_media_km
FROM performance_semanal
ORDER BY dia_semana;


-- ============================================================================
-- CONSULTA 9: Matriz de Correlação: Distância vs Valor vs Tempo de Espera
-- ============================================================================
-- Objetivo: Entender relação entre métricas operacionais
-- ----------------------------------------------------------------------------

WITH metricas_correlacao AS (
    SELECT 
        v.vec_typ,
        f.rid_dst,
        f.bkg_val,
        f.drv_tim_acp,
        f.psg_tim_bdg,
        (f.drv_tim_acp + f.psg_tim_bdg) AS tempo_total_espera
    FROM dw.car_trp f
    INNER JOIN dw.dim_vec v ON f.vec_srk = v.vec_key
    INNER JOIN dw.dim_sts s ON f.sts_srk = s.sts_key
    WHERE s.bkg_sts = 'Success'
        AND f.rid_dst IS NOT NULL
        AND f.bkg_val IS NOT NULL
        AND f.drv_tim_acp IS NOT NULL
        AND f.psg_tim_bdg IS NOT NULL
),
estatisticas_veiculo AS (
    SELECT 
        vec_typ,
        COUNT(*) AS total_viagens,
        AVG(rid_dst) AS distancia_media,
        AVG(bkg_val) AS valor_medio,
        AVG(tempo_total_espera) AS tempo_espera_medio,
        AVG(bkg_val / NULLIF(rid_dst, 0)) AS valor_por_km,
        STDDEV(bkg_val) AS desvio_valor,
        STDDEV(rid_dst) AS desvio_distancia
    FROM metricas_correlacao
    GROUP BY vec_typ
)
SELECT 
    vec_typ AS tipo_veiculo,
    total_viagens,
    ROUND(distancia_media, 2) AS distancia_media_km,
    ROUND(valor_medio, 2) AS valor_medio,
    ROUND(tempo_espera_medio / 60.0, 2) AS tempo_espera_medio_min,
    ROUND(valor_por_km, 2) AS valor_por_km,
    ROUND(desvio_valor, 2) AS variabilidade_valor,
    ROUND(desvio_distancia, 2) AS variabilidade_distancia
FROM estatisticas_veiculo
ORDER BY total_viagens DESC;


-- ============================================================================
-- CONSULTA 10: Ranking de Rotas por Lucratividade e Eficiência
-- ============================================================================
-- Objetivo: Identificar rotas mais lucrativas considerando múltiplos fatores

WITH metricas_rotas AS (
    SELECT 
        r.pck_loc,
        r.drp_loc,
        COUNT(*) AS total_viagens,
        SUM(CASE WHEN s.bkg_sts = 'Success' THEN 1 ELSE 0 END) AS viagens_sucesso,
        SUM(CASE WHEN s.bkg_sts = 'Success' THEN f.bkg_val ELSE 0 END) AS receita_total,
        AVG(CASE WHEN s.bkg_sts = 'Success' THEN f.bkg_val END) AS valor_medio,
        AVG(CASE WHEN s.bkg_sts = 'Success' THEN f.rid_dst END) AS distancia_media,
        AVG(CASE WHEN s.bkg_sts = 'Success' THEN f.drv_tim_acp END) AS tempo_aceitacao,
        AVG(CASE WHEN s.bkg_sts = 'Success' THEN f.drv_rtg END) AS rating_medio
    FROM dw.car_trp f
    INNER JOIN dw.dim_rot r ON f.rot_srk = r.rot_key
    INNER JOIN dw.dim_sts s ON f.sts_srk = s.sts_key
    GROUP BY r.pck_loc, r.drp_loc
    HAVING COUNT(*) >= 5
),
ranking_rotas AS (
    SELECT 
        *,
        ROUND(100.0 * viagens_sucesso / NULLIF(total_viagens, 0), 2) AS taxa_sucesso,
        ROUND(receita_total / NULLIF(viagens_sucesso, 0), 2) AS ticket_medio,
        ROUND(valor_medio / NULLIF(distancia_media, 0), 2) AS valor_por_km,
        ROW_NUMBER() OVER (ORDER BY receita_total DESC) AS rank_receita,
        ROW_NUMBER() OVER (ORDER BY viagens_sucesso DESC) AS rank_volume
    FROM metricas_rotas
)
SELECT 
    pck_loc AS origem,
    drp_loc AS destino,
    total_viagens,
    viagens_sucesso,
    taxa_sucesso AS taxa_sucesso_pct,
    ROUND(receita_total, 2) AS receita_total,
    ticket_medio,
    ROUND(distancia_media, 2) AS distancia_media_km,
    valor_por_km,
    ROUND(tempo_aceitacao / 60.0, 2) AS tempo_aceitacao_min,
    ROUND(rating_medio, 2) AS rating_motorista,
    rank_receita,
    rank_volume
FROM ranking_rotas
ORDER BY receita_total DESC;