-- =====================================================================
-- PsicoHub - Plataforma de Gestão Integrada para Organizações de Psicologia
-- Script de criação do banco de dados (MySQL 8.0.16+)
-- Fonte: Capítulo 19 (DER lógico e dicionário de dados) - AV3 AOO
-- 39 tabelas | todos os dados são fictícios | sem dado clínico,
-- sem senha em texto puro e sem número de cartão.
-- =====================================================================

DROP DATABASE IF EXISTS psicohub;
CREATE DATABASE psicohub
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;
USE psicohub;

SET FOREIGN_KEY_CHECKS = 0;

-- =====================================================================
-- MÓDULO 1 - IDENTIDADE, ACESSO E ADMINISTRAÇÃO (8 tabelas)
-- =====================================================================

-- Papel que agrupa permissões (RN-001)
CREATE TABLE perfil (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  nome       ENUM('ADMINISTRADOR','PSICOLOGO','ATENDENTE','CLIENTE') NOT NULL,
  descricao  VARCHAR(200) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_perfil_nome (nome)
) ENGINE=InnoDB;

-- Autorização atômica sobre um recurso (RN-001)
CREATE TABLE permissao (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  codigo     VARCHAR(60)  NOT NULL,
  recurso    VARCHAR(60)  NOT NULL,
  operacao   ENUM('CRIAR','CONSULTAR','ALTERAR','INATIVAR','EXECUTAR') NOT NULL,
  descricao  VARCHAR(200) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_permissao_codigo (codigo)
) ENGINE=InnoDB;

-- Pessoa com credenciais de acesso e um perfil principal (RN-001 a RN-005)
CREATE TABLE usuario (
  id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  perfil_id        BIGINT UNSIGNED NOT NULL,
  nome             VARCHAR(120) NOT NULL,
  email            VARCHAR(160) NOT NULL,
  senha_hash       VARCHAR(255) NULL COMMENT 'Hash com salt (bcrypt/Argon2). Nulo até o aceite do convite.',
  situacao         ENUM('PENDENTE','ATIVO','INATIVO','BLOQUEADO') NOT NULL DEFAULT 'PENDENTE',
  ultimo_acesso_em DATETIME NULL,
  criado_em        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  atualizado_em    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_usuario_email (email),
  CONSTRAINT fk_usuario_perfil FOREIGN KEY (perfil_id) REFERENCES perfil (id)
) ENGINE=InnoDB;

-- Associação N:N perfil x permissão
CREATE TABLE perfil_permissao (
  perfil_id     BIGINT UNSIGNED NOT NULL,
  permissao_id  BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (perfil_id, permissao_id),
  CONSTRAINT fk_perfperm_perfil    FOREIGN KEY (perfil_id)    REFERENCES perfil (id)    ON DELETE CASCADE,
  CONSTRAINT fk_perfperm_permissao FOREIGN KEY (permissao_id) REFERENCES permissao (id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- Ajuste individual de permissão (RN-001, RN-006)
CREATE TABLE usuario_permissao (
  usuario_id       BIGINT UNSIGNED NOT NULL,
  permissao_id     BIGINT UNSIGNED NOT NULL,
  concedida        TINYINT(1) NOT NULL COMMENT '1 = concede além do perfil; 0 = revoga permissão do perfil',
  ajustado_por_id  BIGINT UNSIGNED NOT NULL,
  ajustado_em      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (usuario_id, permissao_id),
  CONSTRAINT fk_usperm_usuario    FOREIGN KEY (usuario_id)      REFERENCES usuario (id),
  CONSTRAINT fk_usperm_permissao  FOREIGN KEY (permissao_id)    REFERENCES permissao (id),
  CONSTRAINT fk_usperm_ajustador  FOREIGN KEY (ajustado_por_id) REFERENCES usuario (id)
) ENGINE=InnoDB;

-- Convite de cadastro / redefinição de senha, uso único (RN-004)
CREATE TABLE convite_acesso (
  id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  usuario_id     BIGINT UNSIGNED NOT NULL,
  tipo           ENUM('CADASTRO','REDEFINICAO_SENHA') NOT NULL,
  token_hash     CHAR(64) NOT NULL COMMENT 'SHA-256 do token; o token em si não é guardado',
  expira_em      DATETIME NOT NULL,
  utilizado_em   DATETIME NULL,
  criado_por_id  BIGINT UNSIGNED NULL COMMENT 'Nulo na redefinição de senha',
  criado_em      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_convite_token (token_hash),
  CONSTRAINT fk_convite_usuario FOREIGN KEY (usuario_id)    REFERENCES usuario (id),
  CONSTRAINT fk_convite_criador FOREIGN KEY (criado_por_id) REFERENCES usuario (id)
) ENGINE=InnoDB;

-- Auditoria imutável (RN-006): o SGBD só concede INSERT e SELECT
CREATE TABLE registro_auditoria (
  id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  autor_id       BIGINT UNSIGNED NULL COMMENT 'Nulo quando executada pelo sistema/temporizador',
  acao           VARCHAR(60)  NOT NULL,
  tipo_objeto    VARCHAR(60)  NOT NULL,
  objeto_id      BIGINT UNSIGNED NULL,
  data_hora      DATETIME(3)  NOT NULL,
  justificativa  VARCHAR(300) NULL,
  detalhes       JSON NULL COMMENT 'Valores anteriores/novos, sem senhas',
  PRIMARY KEY (id),
  KEY ix_auditoria_autor_data (autor_id, data_hora),
  KEY ix_auditoria_objeto (tipo_objeto, objeto_id),
  CONSTRAINT fk_auditoria_autor FOREIGN KEY (autor_id) REFERENCES usuario (id)
) ENGINE=InnoDB;

-- Parâmetros globais (RN-014, RN-026, RN-038, RNF-014)
CREATE TABLE configuracao_sistema (
  chave              VARCHAR(80)  NOT NULL,
  valor              VARCHAR(200) NOT NULL,
  descricao          VARCHAR(200) NULL,
  atualizado_por_id  BIGINT UNSIGNED NULL,
  atualizado_em      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (chave),
  CONSTRAINT fk_config_atualizador FOREIGN KEY (atualizado_por_id) REFERENCES usuario (id)
) ENGINE=InnoDB;

-- =====================================================================
-- MÓDULO 2 - CADASTROS: PSICÓLOGOS E CLIENTES (5 tabelas)
-- =====================================================================

CREATE TABLE area_atuacao (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  nome       VARCHAR(80)  NOT NULL,
  descricao  VARCHAR(200) NULL,
  ativa      TINYINT(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (id),
  UNIQUE KEY uk_area_nome (nome)
) ENGINE=InnoDB;

-- usuario_id opcional: cadastro administrativo existe com ou sem conta (RN-041)
CREATE TABLE psicologo (
  id                     BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  usuario_id             BIGINT UNSIGNED NULL,
  nome                   VARCHAR(120) NOT NULL,
  registro_profissional  VARCHAR(20)  NOT NULL,
  email_contato          VARCHAR(160) NULL,
  telefone               VARCHAR(20)  NULL,
  situacao               ENUM('ATIVO','INATIVO') NOT NULL DEFAULT 'ATIVO',
  criado_em              DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  atualizado_em          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_psicologo_usuario (usuario_id),
  UNIQUE KEY uk_psicologo_registro (registro_profissional),
  CONSTRAINT fk_psicologo_usuario FOREIGN KEY (usuario_id) REFERENCES usuario (id)
) ENGINE=InnoDB;

-- RN-010
CREATE TABLE psicologo_area_atuacao (
  psicologo_id     BIGINT UNSIGNED NOT NULL,
  area_atuacao_id  BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (psicologo_id, area_atuacao_id),
  CONSTRAINT fk_psarea_psicologo FOREIGN KEY (psicologo_id)    REFERENCES psicologo (id)    ON DELETE CASCADE,
  CONSTRAINT fk_psarea_area      FOREIGN KEY (area_atuacao_id) REFERENCES area_atuacao (id)
) ENGINE=InnoDB;

CREATE TABLE cliente (
  id                  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  usuario_id          BIGINT UNSIGNED NULL,
  nome                VARCHAR(120) NOT NULL,
  cpf                 CHAR(11)     NULL COMMENT 'CPF fictício, apenas dígitos',
  data_nascimento     DATE         NULL,
  email               VARCHAR(160) NULL,
  telefone            VARCHAR(20)  NULL,
  nome_responsavel    VARCHAR(120) NULL,
  contato_responsavel VARCHAR(160) NULL,
  situacao            ENUM('ATIVO','INATIVO','EM_ESPERA') NOT NULL DEFAULT 'ATIVO',
  nivel_urgencia      TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'Escala administrativa 0-3; nunca dado clínico (RN-024)',
  criado_em           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  atualizado_em       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_cliente_usuario (usuario_id),
  UNIQUE KEY uk_cliente_cpf (cpf),
  CONSTRAINT fk_cliente_usuario FOREIGN KEY (usuario_id) REFERENCES usuario (id),
  CONSTRAINT ck_cliente_urgencia CHECK (nivel_urgencia BETWEEN 0 AND 3)
) ENGINE=InnoDB;

-- Um único vínculo ativo por par psicólogo/cliente (RN-011)
CREATE TABLE vinculo (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  psicologo_id  BIGINT UNSIGNED NOT NULL,
  cliente_id    BIGINT UNSIGNED NOT NULL,
  data_inicio   DATE NOT NULL,
  data_fim      DATE NULL,
  situacao      ENUM('ATIVO','ENCERRADO') NOT NULL DEFAULT 'ATIVO',
  chave_ativo   TINYINT(1) GENERATED ALWAYS AS (IF(situacao = 'ATIVO', 1, NULL)) STORED,
  PRIMARY KEY (id),
  UNIQUE KEY uk_vinculo_ativo (psicologo_id, cliente_id, chave_ativo),
  CONSTRAINT fk_vinculo_psicologo FOREIGN KEY (psicologo_id) REFERENCES psicologo (id),
  CONSTRAINT fk_vinculo_cliente   FOREIGN KEY (cliente_id)   REFERENCES cliente (id),
  CONSTRAINT ck_vinculo_datas CHECK (data_fim IS NULL OR data_fim >= data_inicio)
) ENGINE=InnoDB;

-- =====================================================================
-- MÓDULO 3 - AGENDA E ATENDIMENTO (4 tabelas)
-- =====================================================================

CREATE TABLE disponibilidade (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  psicologo_id  BIGINT UNSIGNED NOT NULL,
  dia_semana    TINYINT UNSIGNED NOT NULL COMMENT '1 = segunda ... 7 = domingo',
  hora_inicio   TIME NOT NULL,
  hora_fim      TIME NOT NULL,
  modalidade    ENUM('PRESENCIAL','ONLINE','AMBAS') NOT NULL DEFAULT 'AMBAS',
  ativa         TINYINT(1) NOT NULL DEFAULT 1,
  criado_em     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_disp_psicologo_dia (psicologo_id, dia_semana),
  CONSTRAINT fk_disp_psicologo FOREIGN KEY (psicologo_id) REFERENCES psicologo (id),
  CONSTRAINT ck_disp_horas CHECK (hora_fim > hora_inicio),
  CONSTRAINT ck_disp_dia   CHECK (dia_semana BETWEEN 1 AND 7)
) ENGINE=InnoDB;

-- Ciclo de vida da consulta; reserva provisória de 15 min (RN-013 a RN-016)
CREATE TABLE agendamento (
  id                  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  psicologo_id        BIGINT UNSIGNED NOT NULL,
  cliente_id          BIGINT UNSIGNED NOT NULL,
  area_atuacao_id     BIGINT UNSIGNED NOT NULL,
  data_hora_inicio    DATETIME NOT NULL,
  data_hora_fim       DATETIME NOT NULL,
  modalidade          ENUM('PRESENCIAL','ONLINE') NOT NULL,
  situacao            ENUM('AGUARDANDO_PAGAMENTO','CONFIRMADO','CANCELADO','CANCELADO_FALTA_PAGAMENTO')
                        NOT NULL DEFAULT 'AGUARDANDO_PAGAMENTO',
  origem              ENUM('DIRETO','REENCAIXE') NOT NULL DEFAULT 'DIRETO',
  valor               DECIMAL(10,2) NOT NULL COMMENT 'Cópia do preço vigente no momento da reserva',
  reserva_expira_em   DATETIME NULL COMMENT 'Fim da reserva provisória (15 min)',
  confirmado_em       DATETIME NULL,
  criado_por_id       BIGINT UNSIGNED NULL COMMENT 'Nulo no reencaixe automático',
  criado_em           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  atualizado_em       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  chave_ativo         TINYINT(1) GENERATED ALWAYS AS
                        (IF(situacao IN ('AGUARDANDO_PAGAMENTO','CONFIRMADO'), 1, NULL)) STORED,
  PRIMARY KEY (id),
  UNIQUE KEY uk_agend_psicologo_horario (psicologo_id, data_hora_inicio, chave_ativo),
  UNIQUE KEY uk_agend_cliente_horario   (cliente_id,   data_hora_inicio, chave_ativo),
  KEY ix_agend_reserva (situacao, reserva_expira_em),
  CONSTRAINT fk_agend_psicologo FOREIGN KEY (psicologo_id)    REFERENCES psicologo (id),
  CONSTRAINT fk_agend_cliente   FOREIGN KEY (cliente_id)      REFERENCES cliente (id),
  CONSTRAINT fk_agend_area      FOREIGN KEY (area_atuacao_id) REFERENCES area_atuacao (id),
  CONSTRAINT fk_agend_criador   FOREIGN KEY (criado_por_id)   REFERENCES usuario (id),
  CONSTRAINT ck_agend_intervalo CHECK (data_hora_fim > data_hora_inicio)
) ENGINE=InnoDB;

-- No máximo um cancelamento por agendamento (RN-017, RN-018)
CREATE TABLE cancelamento (
  id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  agendamento_id     BIGINT UNSIGNED NOT NULL,
  autor_id           BIGINT UNSIGNED NULL COMMENT 'Nulo quando cancelado pelo sistema',
  tipo_autor         ENUM('CLIENTE','PSICOLOGO','ATENDENTE','ADMINISTRADOR','SISTEMA') NOT NULL,
  data_hora          DATETIME NOT NULL,
  motivo             VARCHAR(300) NOT NULL,
  antecedencia_horas DECIMAL(7,2) NOT NULL COMMENT 'Base do cálculo do reembolso',
  PRIMARY KEY (id),
  UNIQUE KEY uk_cancel_agendamento (agendamento_id),
  CONSTRAINT fk_cancel_agendamento FOREIGN KEY (agendamento_id) REFERENCES agendamento (id),
  CONSTRAINT fk_cancel_autor       FOREIGN KEY (autor_id)       REFERENCES usuario (id)
) ENGINE=InnoDB;

-- No máximo um atendimento por agendamento; sem conteúdo clínico (RN-020)
CREATE TABLE atendimento (
  id                       BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  agendamento_id           BIGINT UNSIGNED NOT NULL,
  resultado                ENUM('REALIZADO','FALTA') NOT NULL,
  registrado_por_id        BIGINT UNSIGNED NOT NULL,
  registrado_em            DATETIME NOT NULL,
  observacao_administrativa VARCHAR(300) NULL COMMENT 'Proibido conteúdo clínico',
  PRIMARY KEY (id),
  UNIQUE KEY uk_atend_agendamento (agendamento_id),
  CONSTRAINT fk_atend_agendamento FOREIGN KEY (agendamento_id)    REFERENCES agendamento (id),
  CONSTRAINT fk_atend_psicologo   FOREIGN KEY (registrado_por_id) REFERENCES psicologo (id)
) ENGINE=InnoDB;

-- =====================================================================
-- MÓDULO 4 - LISTA DE ESPERA E REENCAIXE (5 tabelas)
-- =====================================================================

-- Um item ativo por cliente em cada área (RN-021)
CREATE TABLE item_lista_espera (
  id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  cliente_id       BIGINT UNSIGNED NOT NULL,
  area_atuacao_id  BIGINT UNSIGNED NOT NULL,
  psicologo_id     BIGINT UNSIGNED NULL COMMENT 'Psicólogo preferido (opcional)',
  modalidade       ENUM('PRESENCIAL','ONLINE','QUALQUER') NOT NULL DEFAULT 'QUALQUER',
  situacao         ENUM('ATIVO','PAUSADO','REMOVIDO','ATENDIDO') NOT NULL DEFAULT 'ATIVO',
  entrada_em       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  posicao_manual   SMALLINT UNSIGNED NULL COMMENT 'Exige justificativa na auditoria (RN-029)',
  saida_em         DATETIME NULL,
  chave_ativo      TINYINT(1) GENERATED ALWAYS AS
                     (IF(situacao IN ('ATIVO','PAUSADO'), 1, NULL)) STORED,
  PRIMARY KEY (id),
  UNIQUE KEY uk_item_cliente_area (cliente_id, area_atuacao_id, chave_ativo),
  CONSTRAINT fk_item_cliente   FOREIGN KEY (cliente_id)      REFERENCES cliente (id),
  CONSTRAINT fk_item_area      FOREIGN KEY (area_atuacao_id) REFERENCES area_atuacao (id),
  CONSTRAINT fk_item_psicologo FOREIGN KEY (psicologo_id)    REFERENCES psicologo (id)
) ENGINE=InnoDB;

-- Janelas de disponibilidade do cliente (base da aderência, RN-022)
CREATE TABLE janela_espera (
  id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  item_id      BIGINT UNSIGNED NOT NULL,
  dia_semana   TINYINT UNSIGNED NOT NULL COMMENT '1 = segunda ... 7 = domingo',
  hora_inicio  TIME NOT NULL,
  hora_fim     TIME NOT NULL,
  PRIMARY KEY (id),
  CONSTRAINT fk_janela_item FOREIGN KEY (item_id) REFERENCES item_lista_espera (id) ON DELETE CASCADE,
  CONSTRAINT ck_janela_horas CHECK (hora_fim > hora_inicio)
) ENGINE=InnoDB;

-- Padrão Strategy: critérios e pesos da priorização (RN-023, RN-024)
CREATE TABLE politica_priorizacao (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  nome            VARCHAR(80) NOT NULL,
  estrategia      VARCHAR(60) NOT NULL COMMENT 'Ex.: PRIORIZACAO_PADRAO',
  peso_tempo_espera DECIMAL(5,2) NOT NULL DEFAULT 1.00,
  peso_urgencia   DECIMAL(5,2) NOT NULL DEFAULT 1.00,
  peso_aderencia  DECIMAL(5,2) NOT NULL DEFAULT 1.00,
  peso_historico  DECIMAL(5,2) NULL,
  usa_historico   TINYINT(1) NOT NULL DEFAULT 0,
  vigente         TINYINT(1) NOT NULL DEFAULT 0,
  criada_por_id   BIGINT UNSIGNED NOT NULL,
  criada_em       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  chave_vigente   TINYINT(1) GENERATED ALWAYS AS (IF(vigente = 1, 1, NULL)) STORED,
  PRIMARY KEY (id),
  UNIQUE KEY uk_politica_vigente (chave_vigente),
  CONSTRAINT fk_politica_criador FOREIGN KEY (criada_por_id) REFERENCES usuario (id)
) ENGINE=InnoDB;

CREATE TABLE vaga_liberada (
  id                   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  psicologo_id         BIGINT UNSIGNED NOT NULL,
  area_atuacao_id      BIGINT UNSIGNED NOT NULL,
  data_hora_inicio     DATETIME NOT NULL,
  data_hora_fim        DATETIME NOT NULL,
  modalidade           ENUM('PRESENCIAL','ONLINE') NOT NULL,
  gatilho              ENUM('CANCELAMENTO','NOVA_DISPONIBILIDADE') NOT NULL,
  agendamento_origem_id BIGINT UNSIGNED NULL,
  situacao             ENUM('EM_REENCAIXE','OCUPADA','ABERTA_AGENDAMENTO_DIRETO') NOT NULL DEFAULT 'EM_REENCAIXE',
  liberada_em          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  encerrada_em         DATETIME NULL,
  PRIMARY KEY (id),
  KEY ix_vaga_situacao (situacao, data_hora_inicio),
  CONSTRAINT fk_vaga_psicologo FOREIGN KEY (psicologo_id)          REFERENCES psicologo (id),
  CONSTRAINT fk_vaga_area      FOREIGN KEY (area_atuacao_id)       REFERENCES area_atuacao (id),
  CONSTRAINT fk_vaga_agend     FOREIGN KEY (agendamento_origem_id) REFERENCES agendamento (id)
) ENGINE=InnoDB;

-- Uma oferta aberta por vaga (RN-025); prazos de 2 h / 30 min (RN-026)
CREATE TABLE oferta_vaga (
  id                  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  vaga_id             BIGINT UNSIGNED NOT NULL,
  item_id             BIGINT UNSIGNED NOT NULL,
  politica_id         BIGINT UNSIGNED NOT NULL,
  pontuacao           DECIMAL(8,2) NOT NULL,
  pontos_tempo_espera DECIMAL(8,2) NOT NULL,
  pontos_urgencia     DECIMAL(8,2) NOT NULL,
  pontos_aderencia    DECIMAL(8,2) NOT NULL,
  pontos_historico    DECIMAL(8,2) NULL,
  posicao_na_fila     SMALLINT UNSIGNED NOT NULL,
  situacao            ENUM('ABERTA','ACEITA','RECUSADA','EXPIRADA','PAGAMENTO_NAO_CONCLUIDO')
                        NOT NULL DEFAULT 'ABERTA',
  ofertada_em         DATETIME NOT NULL,
  expira_em           DATETIME NOT NULL,
  respondida_em       DATETIME NULL,
  agendamento_id      BIGINT UNSIGNED NULL COMMENT 'Agendamento gerado no aceite',
  chave_aberta        TINYINT(1) GENERATED ALWAYS AS (IF(situacao = 'ABERTA', 1, NULL)) STORED,
  PRIMARY KEY (id),
  UNIQUE KEY uk_oferta_agendamento (agendamento_id),
  UNIQUE KEY uk_oferta_vaga_aberta (vaga_id, chave_aberta),
  UNIQUE KEY uk_oferta_vaga_item   (vaga_id, item_id),
  KEY ix_oferta_expiracao (situacao, expira_em),
  CONSTRAINT fk_oferta_vaga     FOREIGN KEY (vaga_id)        REFERENCES vaga_liberada (id),
  CONSTRAINT fk_oferta_item     FOREIGN KEY (item_id)        REFERENCES item_lista_espera (id),
  CONSTRAINT fk_oferta_politica FOREIGN KEY (politica_id)    REFERENCES politica_priorizacao (id),
  CONSTRAINT fk_oferta_agend    FOREIGN KEY (agendamento_id) REFERENCES agendamento (id)
) ENGINE=InnoDB;

-- =====================================================================
-- MÓDULO 5 - NOTIFICAÇÕES (3 tabelas)
-- =====================================================================

CREATE TABLE notificacao (
  id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  usuario_id   BIGINT UNSIGNED NOT NULL,
  tipo         ENUM('AGENDAMENTO','CONFIRMACAO','LEMBRETE','CANCELAMENTO','REMARCACAO',
                    'OFERTA_VAGA','COBRANCA','IMPORTACAO') NOT NULL,
  titulo       VARCHAR(120) NOT NULL,
  mensagem     VARCHAR(500) NOT NULL,
  objeto_tipo  VARCHAR(40) NULL,
  objeto_id    BIGINT UNSIGNED NULL,
  criada_em    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  lida_em      DATETIME NULL,
  PRIMARY KEY (id),
  KEY ix_notif_usuario (usuario_id, lida_em, criada_em),
  CONSTRAINT fk_notif_usuario FOREIGN KEY (usuario_id) REFERENCES usuario (id)
) ENGINE=InnoDB;

CREATE TABLE preferencia_notificacao (
  usuario_id     BIGINT UNSIGNED NOT NULL,
  categoria      ENUM('AGENDA','OFERTA_VAGA','COBRANCA') NOT NULL,
  email_ativo    TINYINT(1) NOT NULL DEFAULT 0,
  atualizado_em  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (usuario_id, categoria),
  CONSTRAINT fk_pref_usuario FOREIGN KEY (usuario_id) REFERENCES usuario (id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE envio_email (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  notificacao_id  BIGINT UNSIGNED NULL COMMENT 'Nula nos e-mails transacionais',
  usuario_id      BIGINT UNSIGNED NOT NULL,
  categoria       ENUM('TRANSACIONAL','COMPLEMENTAR') NOT NULL,
  destinatario    VARCHAR(160) NOT NULL,
  assunto         VARCHAR(160) NOT NULL,
  situacao        ENUM('PENDENTE','ENVIADO','FALHA') NOT NULL DEFAULT 'PENDENTE',
  tentativas      TINYINT UNSIGNED NOT NULL DEFAULT 0,
  id_externo      VARCHAR(80) NULL,
  criado_em       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  enviado_em      DATETIME NULL,
  PRIMARY KEY (id),
  CONSTRAINT fk_email_notificacao FOREIGN KEY (notificacao_id) REFERENCES notificacao (id),
  CONSTRAINT fk_email_usuario     FOREIGN KEY (usuario_id)     REFERENCES usuario (id)
) ENGINE=InnoDB;

-- =====================================================================
-- MÓDULO 6 - ASSINATURA E FATURAMENTO (5 tabelas)
-- =====================================================================

CREATE TABLE organizacao (
  id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  razao_social   VARCHAR(160) NOT NULL,
  nome_fantasia  VARCHAR(120) NULL,
  cnpj           CHAR(14) NOT NULL COMMENT 'CNPJ fictício, apenas dígitos',
  email_contato  VARCHAR(160) NOT NULL,
  situacao       ENUM('ATIVA','INATIVA') NOT NULL DEFAULT 'ATIVA',
  criado_em      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_organizacao_cnpj (cnpj)
) ENGINE=InnoDB;

-- RN-034
CREATE TABLE plano_assinatura (
  id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  nome               ENUM('ESSENCIAL','PROFISSIONAL','ORGANIZACAO') NOT NULL,
  limite_psicologos  SMALLINT UNSIGNED NULL COMMENT 'Nulo = ilimitado',
  valor_mensal       DECIMAL(10,2) NOT NULL,
  dias_teste         TINYINT UNSIGNED NOT NULL DEFAULT 14,
  dias_arrependimento TINYINT UNSIGNED NOT NULL DEFAULT 7,
  ativo              TINYINT(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (id),
  UNIQUE KEY uk_plano_nome (nome)
) ENGINE=InnoDB;

-- RN-035: cancelamento vale a partir do ciclo seguinte
CREATE TABLE assinatura (
  id                        BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  organizacao_id            BIGINT UNSIGNED NOT NULL,
  plano_id                  BIGINT UNSIGNED NOT NULL,
  situacao                  ENUM('TESTE','ATIVA','CANCELAMENTO_AGENDADO','CANCELADA','INADIMPLENTE')
                              NOT NULL DEFAULT 'TESTE',
  inicio_em                 DATE NOT NULL,
  fim_teste_em              DATE NULL,
  ciclo_inicio              DATE NOT NULL,
  ciclo_fim                 DATE NOT NULL,
  proxima_cobranca_em       DATE NULL,
  cancelamento_solicitado_em DATETIME NULL,
  criada_em                 DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  CONSTRAINT fk_assin_organizacao FOREIGN KEY (organizacao_id) REFERENCES organizacao (id),
  CONSTRAINT fk_assin_plano       FOREIGN KEY (plano_id)       REFERENCES plano_assinatura (id)
) ENGINE=InnoDB;

-- RN-031: exatamente um responsável pagador (cliente OU organização)
CREATE TABLE fatura (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  numero          VARCHAR(20) NOT NULL,
  cliente_id      BIGINT UNSIGNED NULL,
  organizacao_id  BIGINT UNSIGNED NULL,
  valor_total     DECIMAL(10,2) NOT NULL,
  emitida_em      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  vencimento      DATETIME NOT NULL,
  situacao        ENUM('ABERTA','PAGA','VENCIDA','CANCELADA') NOT NULL DEFAULT 'ABERTA',
  PRIMARY KEY (id),
  UNIQUE KEY uk_fatura_numero (numero),
  CONSTRAINT fk_fatura_cliente     FOREIGN KEY (cliente_id)     REFERENCES cliente (id),
  CONSTRAINT fk_fatura_organizacao FOREIGN KEY (organizacao_id) REFERENCES organizacao (id),
  CONSTRAINT ck_fatura_pagador CHECK ((cliente_id IS NULL) <> (organizacao_id IS NULL))
) ENGINE=InnoDB;

-- Cobrança de um agendamento OU de uma assinatura
CREATE TABLE cobranca (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  fatura_id       BIGINT UNSIGNED NOT NULL,
  tipo            ENUM('AGENDAMENTO','ASSINATURA') NOT NULL,
  agendamento_id  BIGINT UNSIGNED NULL,
  assinatura_id   BIGINT UNSIGNED NULL,
  descricao       VARCHAR(200) NOT NULL,
  valor           DECIMAL(10,2) NOT NULL,
  vencimento      DATETIME NOT NULL COMMENT 'No agendamento, o fim da reserva provisória',
  situacao        ENUM('PENDENTE','PAGA','VENCIDA','CANCELADA','REEMBOLSADA_PARCIAL','REEMBOLSADA')
                    NOT NULL DEFAULT 'PENDENTE',
  criada_em       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_cobranca_agendamento (agendamento_id),
  CONSTRAINT fk_cobranca_fatura      FOREIGN KEY (fatura_id)      REFERENCES fatura (id),
  CONSTRAINT fk_cobranca_agendamento FOREIGN KEY (agendamento_id) REFERENCES agendamento (id),
  CONSTRAINT fk_cobranca_assinatura  FOREIGN KEY (assinatura_id)  REFERENCES assinatura (id),
  CONSTRAINT ck_cobranca_origem CHECK (
       (tipo = 'AGENDAMENTO' AND agendamento_id IS NOT NULL AND assinatura_id IS NULL)
    OR (tipo = 'ASSINATURA'  AND assinatura_id  IS NOT NULL AND agendamento_id IS NULL))
) ENGINE=InnoDB;

-- =====================================================================
-- MÓDULO 7 - PAGAMENTOS E REEMBOLSO (3 tabelas)
-- Nenhum campo de número ou código de cartão (RNF-004)
-- =====================================================================

CREATE TABLE pagamento (
  id                    BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  cobranca_id           BIGINT UNSIGNED NOT NULL,
  metodo                ENUM('PIX','CARTAO') NOT NULL,
  valor                 DECIMAL(10,2) NOT NULL,
  situacao              ENUM('PENDENTE','APROVADO','RECUSADO','ESTORNADO') NOT NULL DEFAULT 'PENDENTE',
  id_transacao_provedor VARCHAR(80) NULL COMMENT 'Base da idempotência',
  criado_em             DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  pago_em               DATETIME NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_pagamento_transacao (id_transacao_provedor),
  CONSTRAINT fk_pagamento_cobranca FOREIGN KEY (cobranca_id) REFERENCES cobranca (id)
) ENGINE=InnoDB;

-- Evita processar duas vezes o mesmo evento (RN-032, RNF-007)
CREATE TABLE retorno_provedor (
  id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  id_evento_provedor VARCHAR(80) NOT NULL,
  tipo               ENUM('PAGAMENTO_APROVADO','PAGAMENTO_FALHOU','REEMBOLSO_PROCESSADO','REEMBOLSO_FALHOU') NOT NULL,
  pagamento_id       BIGINT UNSIGNED NULL,
  payload            JSON NOT NULL COMMENT 'Conteúdo recebido, sem dados de cartão',
  recebido_em        DATETIME(3) NOT NULL,
  processado_em      DATETIME(3) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_retorno_evento (id_evento_provedor),
  CONSTRAINT fk_retorno_pagamento FOREIGN KEY (pagamento_id) REFERENCES pagamento (id)
) ENGINE=InnoDB;

-- Um reembolso por cancelamento (RN-018, RN-019, RN-032)
CREATE TABLE reembolso (
  id                     BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  pagamento_id           BIGINT UNSIGNED NOT NULL,
  cancelamento_id        BIGINT UNSIGNED NOT NULL,
  percentual             DECIMAL(5,2) NOT NULL COMMENT '80, 50, 20, 0 ou 100',
  valor                  DECIMAL(10,2) NOT NULL,
  situacao               ENUM('SOLICITADO','PROCESSADO','FALHOU') NOT NULL DEFAULT 'SOLICITADO',
  id_reembolso_provedor  VARCHAR(80) NULL,
  solicitado_em          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  processado_em          DATETIME NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_reembolso_cancelamento (cancelamento_id),
  UNIQUE KEY uk_reembolso_provedor (id_reembolso_provedor),
  CONSTRAINT fk_reembolso_pagamento    FOREIGN KEY (pagamento_id)    REFERENCES pagamento (id),
  CONSTRAINT fk_reembolso_cancelamento FOREIGN KEY (cancelamento_id) REFERENCES cancelamento (id)
) ENGINE=InnoDB;

-- =====================================================================
-- MÓDULO 8 - PARÂMETROS FINANCEIROS (2 tabelas)
-- =====================================================================

-- Preço geral, por psicólogo ou por área, com vigência (RN-033)
CREATE TABLE preco_sessao (
  id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  valor            DECIMAL(10,2) NOT NULL,
  psicologo_id     BIGINT UNSIGNED NULL COMMENT 'Nulo = não restringe',
  area_atuacao_id  BIGINT UNSIGNED NULL COMMENT 'Nula = não restringe',
  vigente_desde    DATE NOT NULL,
  vigente_ate      DATE NULL,
  criado_por_id    BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (id),
  CONSTRAINT fk_preco_psicologo FOREIGN KEY (psicologo_id)    REFERENCES psicologo (id),
  CONSTRAINT fk_preco_area      FOREIGN KEY (area_atuacao_id) REFERENCES area_atuacao (id),
  CONSTRAINT fk_preco_criador   FOREIGN KEY (criado_por_id)   REFERENCES usuario (id),
  CONSTRAINT ck_preco_valor CHECK (valor >= 0)
) ENGINE=InnoDB;

-- Percentuais de reembolso configuráveis (RN-018, RN-019, RNF-014)
CREATE TABLE faixa_reembolso (
  id                      BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  condicao                ENUM('ANTECEDENCIA','AUSENCIA_SEM_AVISO') NOT NULL,
  antecedencia_min_horas  SMALLINT UNSIGNED NULL COMMENT '48, 24, 0; nula na ausência sem aviso',
  percentual              DECIMAL(5,2) NOT NULL,
  ativa                   TINYINT(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (id),
  CONSTRAINT ck_faixa_percentual CHECK (percentual BETWEEN 0 AND 100)
) ENGINE=InnoDB;

-- =====================================================================
-- MÓDULO 9 - IMPORTAÇÃO DE DADOS (4 tabelas)
-- =====================================================================

CREATE TABLE lote_importacao (
  id                  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  responsavel_id      BIGINT UNSIGNED NOT NULL,
  nome_arquivo        VARCHAR(200) NOT NULL,
  formato             ENUM('CSV','XLSX') NOT NULL,
  tipo_cadastro       ENUM('PSICOLOGOS','CLIENTES') NOT NULL,
  situacao            ENUM('RECEBIDO','VALIDADO','EM_REVISAO','CONSOLIDADO','CANCELADO') NOT NULL DEFAULT 'RECEBIDO',
  total_registros     INT UNSIGNED NOT NULL DEFAULT 0,
  total_validos       INT UNSIGNED NOT NULL DEFAULT 0,
  total_inconsistentes INT UNSIGNED NOT NULL DEFAULT 0,
  total_duplicidades  INT UNSIGNED NOT NULL DEFAULT 0,
  importado_em        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  consolidado_em      DATETIME NULL,
  PRIMARY KEY (id),
  CONSTRAINT fk_lote_responsavel FOREIGN KEY (responsavel_id) REFERENCES usuario (id)
) ENGINE=InnoDB;

-- dados_originais nunca é alterado; nada é descartado em silêncio (RN-039, RN-041)
CREATE TABLE registro_importado (
  id                  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  lote_id             BIGINT UNSIGNED NOT NULL,
  numero_linha        INT UNSIGNED NOT NULL,
  dados_originais     JSON NOT NULL,
  dados_higienizados  JSON NULL,
  situacao            ENUM('VALIDO','CORRIGIDO','INCONSISTENTE','DUPLICADO','CONSOLIDADO') NOT NULL DEFAULT 'VALIDO',
  cliente_id          BIGINT UNSIGNED NULL,
  psicologo_id        BIGINT UNSIGNED NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_registro_lote_linha (lote_id, numero_linha),
  CONSTRAINT fk_regimp_lote      FOREIGN KEY (lote_id)      REFERENCES lote_importacao (id),
  CONSTRAINT fk_regimp_cliente   FOREIGN KEY (cliente_id)   REFERENCES cliente (id),
  CONSTRAINT fk_regimp_psicologo FOREIGN KEY (psicologo_id) REFERENCES psicologo (id),
  CONSTRAINT ck_regimp_destino CHECK (cliente_id IS NULL OR psicologo_id IS NULL)
) ENGINE=InnoDB;

CREATE TABLE inconsistencia_importacao (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  registro_id       BIGINT UNSIGNED NOT NULL,
  campo             VARCHAR(60) NOT NULL,
  tipo              ENUM('CAMPO_OBRIGATORIO','FORMATO_INVALIDO','VALOR_INVALIDO','OUTRA') NOT NULL,
  descricao         VARCHAR(300) NOT NULL,
  valor_original    VARCHAR(200) NULL,
  resolvida         TINYINT(1) NOT NULL DEFAULT 0,
  resolvida_por_id  BIGINT UNSIGNED NULL,
  resolvida_em      DATETIME NULL,
  PRIMARY KEY (id),
  CONSTRAINT fk_inconsist_registro FOREIGN KEY (registro_id)      REFERENCES registro_importado (id),
  CONSTRAINT fk_inconsist_resolvedor FOREIGN KEY (resolvida_por_id) REFERENCES usuario (id)
) ENGINE=InnoDB;

-- Fusão/manutenção só com decisão humana (RN-040)
CREATE TABLE sugestao_duplicidade (
  id                      BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  registro_id             BIGINT UNSIGNED NOT NULL,
  registro_duplicado_id   BIGINT UNSIGNED NULL,
  cliente_existente_id    BIGINT UNSIGNED NULL,
  psicologo_existente_id  BIGINT UNSIGNED NULL,
  similaridade            DECIMAL(5,2) NOT NULL COMMENT '0 a 100',
  situacao                ENUM('PENDENTE','FUNDIDA','MANTIDA_SEPARADA') NOT NULL DEFAULT 'PENDENTE',
  decidida_por_id         BIGINT UNSIGNED NULL,
  decidida_em             DATETIME NULL,
  PRIMARY KEY (id),
  CONSTRAINT fk_sugdup_registro   FOREIGN KEY (registro_id)            REFERENCES registro_importado (id),
  CONSTRAINT fk_sugdup_duplicado  FOREIGN KEY (registro_duplicado_id)  REFERENCES registro_importado (id),
  CONSTRAINT fk_sugdup_cliente    FOREIGN KEY (cliente_existente_id)   REFERENCES cliente (id),
  CONSTRAINT fk_sugdup_psicologo  FOREIGN KEY (psicologo_existente_id) REFERENCES psicologo (id),
  CONSTRAINT fk_sugdup_decisor    FOREIGN KEY (decidida_por_id)        REFERENCES usuario (id),
  CONSTRAINT ck_sugdup_decisao CHECK (situacao = 'PENDENTE' OR decidida_por_id IS NOT NULL)
) ENGINE=InnoDB;

SET FOREIGN_KEY_CHECKS = 1;

-- =====================================================================
-- DADOS DE REFERÊNCIA (valores definidos nas regras de negócio)
-- Os valores monetários dos planos NÃO constam no documento: ajuste-os.
-- =====================================================================

INSERT INTO perfil (nome, descricao) VALUES
  ('ADMINISTRADOR', 'Gerencia usuários, configurações, preços, políticas e auditoria'),
  ('PSICOLOGO',     'Gerencia sua agenda e registra atendimentos'),
  ('ATENDENTE',     'Opera agenda, lista de espera e importações'),
  ('CLIENTE',       'Agenda sessões, paga e acompanha notificações');

INSERT INTO area_atuacao (nome) VALUES
  ('Clínica'), ('Organizacional'), ('Escolar'), ('Hospitalar'),
  ('Social'), ('Jurídica'), ('Esportiva');

-- RN-034: limites por plano; 14 dias de teste e 7 de arrependimento
INSERT INTO plano_assinatura (nome, limite_psicologos, valor_mensal, dias_teste, dias_arrependimento) VALUES
  ('ESSENCIAL',    3,    0.00, 14, 7),   -- valor_mensal: definir
  ('PROFISSIONAL', 15,   0.00, 14, 7),   -- valor_mensal: definir
  ('ORGANIZACAO',  NULL, 0.00, 14, 7);   -- NULL = ilimitado; valor_mensal: definir

-- RN-018 / RN-019: faixas de reembolso (o 100% do cancelamento pelo psicólogo é regra da aplicação)
INSERT INTO faixa_reembolso (condicao, antecedencia_min_horas, percentual) VALUES
  ('ANTECEDENCIA',      48, 80.00),
  ('ANTECEDENCIA',      24, 50.00),
  ('ANTECEDENCIA',       0, 20.00),
  ('AUSENCIA_SEM_AVISO', NULL, 0.00);

-- RN-026 e RN-038 (chaves OFERTA_PRAZO_* e LEMBRETE_ANTECEDENCIA_H); RN-014: reserva de 15 min
INSERT INTO configuracao_sistema (chave, valor, descricao) VALUES
  ('OFERTA_PRAZO_PADRAO_MIN',  '120', 'Prazo (min) para o candidato responder à oferta'),
  ('OFERTA_PRAZO_URGENTE_MIN', '30',  'Prazo (min) quando a sessão ocorre em menos de 24 h'),
  ('RESERVA_PROVISORIA_MIN',   '15',  'Duração da reserva provisória do agendamento'),
  ('LEMBRETE_ANTECEDENCIA_H',  '24',  'Antecedência (h) do lembrete de sessão');

-- =====================================================================
-- IMUTABILIDADE DA AUDITORIA (RN-006) - ajuste usuário/host ao seu ambiente
-- =====================================================================
-- CREATE USER 'psicohub_app'@'%' IDENTIFIED BY 'TROQUE_ESTA_SENHA';
-- Auditoria: somente INSERT e SELECT
-- GRANT SELECT, INSERT ON psicohub.registro_auditoria TO 'psicohub_app'@'%';
-- Demais tabelas: conceda SELECT, INSERT, UPDATE, DELETE tabela a tabela
-- (o MySQL não permite REVOKE parcial de um GRANT em psicohub.*),
-- por exemplo:
-- GRANT SELECT, INSERT, UPDATE, DELETE ON psicohub.usuario TO 'psicohub_app'@'%';
