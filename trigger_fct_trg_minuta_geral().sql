-- Function: trigger_fct_trg_minuta_geral()

-- DROP FUNCTION trigger_fct_trg_minuta_geral();

CREATE OR REPLACE FUNCTION trigger_fct_trg_minuta_geral()
  RETURNS trigger AS
$BODY$
DECLARE
   V_LINHA         varchar(4);
   V_SUBGRUPO      varchar(4);
   V_FATURA        numeric(2) := 0;
   V_PCRESERVA     numeric(6,2);
   V_SALDORESERVA  numeric(15,2);
   V_SOITENSMINUTA numeric(15,2);
   V_REGIAO        numeric(2);
   V_TPCLIENTE     varchar(2);
   V_PROFCLIENTE   varchar(1);
   V_CBO           numeric(6);
   V_NFMANUAL      varchar(1);
   V_CHAVECLI      varchar(10);
   V_CHAVECAT      varchar(12);
   V_CHAVEMIN      varchar(11);
   V_UF            varchar(2);
   V_LOJA_CENTRAL  character varying(3);
   V_UF_Destino    varchar(2);
   V_UF_DEFINE     varchar(2) := 'XX';
   V_chave_la      character varying(8);
   V_chave_grp     character varying(12); 
   V_chave_subgrp  character varying(13);  
   V_chave_linha   character varying(20); 
   V_chave_produto character varying(18); 
   V_chave_geral   character varying(25); 
   V_tem_ST        character varying(1) := ' ';
   V_RESULTADO     varchar(20) := ' ';
   V_ATIVADO       INT := 0;
   loopitemminuta  record;
   V_PREDATADA     INT := 0;
   V_NOTFIN13      character varying(1);

BEGIN
   NEW.cd_chave          := ( NEW.Sg_Loja || LPAD(NEW.nr_minuta::text, 8) );
   NEW.cd_chave_ldtm     := ( NEW.Sg_Loja || to_char(NEW.dt_Minuta ,'YYYYMMDD'));
   NEW.cd_chave_mp       := ( NEW.cd_modo || NEW.cd_plano );
   NEW.Cd_Chave_Con      := ( NEW.Sg_Loja || LPAD(NEW.tp_contrato::text, 2) || 
         LPAD(NEW.tp_financeiro::text, 2) || LPAD(NEW.nr_contrato::text, 8) );

     
   IF TG_OP IN ('INSERT','UPDATE') AND NEW.DT_CANCEL IS NOT NULL THEN
      BEGIN
         SELECT COUNT(*)::INT INTO STRICT V_ATIVADO 
             FROM DBATEZ.CONFIGLOJA 
             WHERE CD_CHAVE='GIV9916' AND 
                    (POSITION('+' IN NR_CONFA) > 0 OR POSITION(NEW.SG_LOJA IN NR_CONFA) > 0);
     EXCEPTION
         WHEN NO_DATA_FOUND THEN
              V_ATIVADO:=0;
     END;        
  
     IF V_ATIVADO <> 0 THEN
        DELETE FROM DBATEZ.ESTOQUE_MOV
                WHERE CD_CHAVE_CON = NEW.SG_LOJA || '9916' || LPAD(NEW.NR_MINUTA::TEXT,8);                       
     END IF;  
   END IF;   

   
   SELECT sg_uf,sg_loja_central into V_UF,V_LOJA_CENTRAL
          from loja where sg_loja = NEW.sg_loja;

   IF (SELECT count(1) from configloja WHERE cd_chave = (lower(V_LOJA_CENTRAL) || '1109')::varchar(7) and fl_conf='S') = 0
      THEN
      RETURN NEW;
   END IF;

   IF NEW.cd_divisao in (1,51) THEN
      SELECT nr_confn into V_PCRESERVA from configloja 
             WHERE cd_chave = lower(V_LOJA_CENTRAL) || '7970';
   ELSIF NEW.cd_divisao in (2,52) THEN
      SELECT nr_confn into V_PCRESERVA from configloja 
             WHERE cd_chave = lower(V_LOJA_CENTRAL) || '7980';
   ELSE
      SELECT nr_confn into V_PCRESERVA from configloja 
             WHERE cd_chave = lower(V_LOJA_CENTRAL) || '7990';
   END IF;

   IF NOT FOUND THEN
      RETURN NEW;
   END IF;
          
   IF TG_OP = 'UPDATE' THEN
      If OLD.tp_financeiro > 0 THEN
         RETURN NEW;
      END IF;
   END IF;
  
   IF NEW.VL_PREDATADA > 0 THEN
      V_PREDATADA := 1;
   END IF;

   V_NOTFIN13 := 'S';
   IF (NEW.QT_PRESTACAO1 + NEW.QT_PRESTACAO2) = 1 THEN
      IF (NEW.DT_1VENCIMENTO - NEW.DT_MINUTA) < 30 THEN
          V_NOTFIN13 := 'N'; -- TRAC #14534
      END IF;
   END IF;

   SELECT substr(no_conf,1,2) into V_REGIAO from configloja WHERE cd_chave='ZIM   1';
   V_CHAVECLI := LPAD(V_REGIAO::text,2) || LPAD(NEW.cd_cliente::text,8);
   If NEW.cd_cliente <> 99999999 THEN
      SELECT tp_cliente into V_TPCLIENTE from cliente WHERE cd_chave = V_CHAVECLI;
      IF NOT FOUND THEN
         V_TPCLIENTE := ' 1';
      ELSIF V_TPCLIENTE <> ' 1' THEN
         IF (SELECT COUNT(1) from documento WHERE cd_chave_cli = V_CHAVECLI AND
              tp_documento in (' 5',' 6')) = 0 THEN
            V_TPCLIENTE := ' 1';
         END IF;
      END IF;
   ELSE
      V_TPCLIENTE := ' 1';
      V_FATURA    := 77;
   END IF;

   SELECT cd_cbo into V_CBO from cliente_novos where pk_cliente_novos = V_CHAVECLI;
   IF NOT FOUND THEN
      V_PROFCLIENTE := 'S';
   ELSE
      SELECT fl_r into V_PROFCLIENTE from tab_ocupacao where pk_ocupacao = V_CBO;
      IF V_PROFCLIENTE = 'N' THEN
         V_FATURA := 15;
         V_RESULTADO := 'CBO';
      END IF;
   END IF;
   
   V_CHAVEMIN := NEW.sg_loja || LPAD(NEW.nr_minuta::text,8);
   V_SOITENSMINUTA := NEW.vl_contrato - COALESCE(NEW.vl_garantia,0) - COALESCE(NEW.vl_garantiadf,0);
   SELECT sg_uf INTO V_UF_Destino from minuta_ent where cd_chave = V_CHAVEMIN;
   IF NOT FOUND THEN
      V_UF_Destino := V_UF;
   END IF;

   SELECT 'S' INTO V_NFMANUAL from minuta_novos WHERE cd_chave_min = V_CHAVEMIN AND sq_novos='00';
   IF NOT FOUND THEN
      V_NFMANUAL := 'N';
   END IF;

   IF (V_TPCLIENTE <> ' 1' or NEW.vl_garantia > 0) and NEW.fl_modovenda <> ' 6'
      THEN
      V_RESULTADO := 'GAR';
      V_FATURA := 15;
   ELSE
      SELECT fl_plano INTO V_tem_ST from minuta_item where cd_chave_min = V_CHAVEMIN
       and fl_plano = '6' limit 1;
      IF FOUND THEN
         V_RESULTADO := 'STB';
         V_FATURA := 15;
      ELSE
         V_tem_ST := ' ';
      END IF;
   END IF;

   IF NEW.cd_modo1 = 'A' AND NEW.fl_modovenda = ' 6' -- Extrato
      THEN
      V_TPCLIENTE := ' 1';
      V_FATURA    := 77;
   END IF;
   
IF (NEW.fl_modovenda = ' 6' or V_TPCLIENTE = ' 1') AND V_FATURA = 0  THEN
   
   FOR loopitemminuta IN select 
       CASE WHEN cd_almoxarifado = 80 THEN 1::numeric(2) ELSE cd_almoxarifado END,
              cd_grupo,cd_produto,fl_plano 
	      from minuta_item where cd_chave_min = V_CHAVEMIN
       LOOP
       IF loopitemminuta.fl_plano = '6' THEN
          V_tem_ST   := loopitemminuta.fl_plano;
       END IF;
       V_CHAVECAT := LPAD(loopitemminuta.cd_almoxarifado::text,2) ||
                     LPAD(loopitemminuta.cd_grupo::text,4) ||
                     LPAD(loopitemminuta.cd_produto::text,6);
 
       SELECT cd_linha,cd_subgrupo INTO V_LINHA,V_SUBGRUPO from catalogo 
              WHERE cd_chave = V_CHAVECAT;                    
 
       V_chave_produto := (V_UF_DEFINE || 'CSA' || LPAD(loopitemminuta.cd_almoxarifado::text,2) || 
                             LPAD(loopitemminuta.cd_grupo::text,4) ||
                             LPAD(loopitemminuta.cd_produto::text,6)); 
       V_chave_grp     := (V_UF_DEFINE || 'CSA' || LPAD(loopitemminuta.cd_almoxarifado::text,2) ||
                             LPAD(loopitemminuta.cd_grupo::text,4));
       V_chave_linha   := (V_UF_DEFINE || 'CSA' || LPAD(loopitemminuta.cd_almoxarifado::text,2) || 
                              LPAD(loopitemminuta.cd_grupo::text,4) ||
                              LPAD(V_SUBGRUPO::text,4) || 
                              LPAD(V_LINHA::text,4)); 
       V_chave_la      := (V_UF_DEFINE || 'CSA' || LPAD(loopitemminuta.cd_almoxarifado::text,2));
       V_chave_subgrp  := (V_UF_DEFINE || 'CSA' || LPAD(loopitemminuta.cd_almoxarifado::text,2) ||
                              LPAD(V_SUBGRUPO::text,4));
 
       SELECT 15 into V_FATURA FROM tab_define 
	      where cd_chave_la = V_chave_la;
       --raise notice 'va_chave_la: %', V_chave_la;
       --raise notice 'FAT: %', V_FATURA;
       IF NOT FOUND THEN
          SELECT 15 into V_FATURA FROM tab_define where cd_chave_grp = V_chave_grp;
	  IF NOT FOUND  THEN
             SELECT 15 into V_FATURA FROM tab_define where cd_chave_subgrp = 
                       V_chave_subgrp;
             IF NOT FOUND THEN
                SELECT 15 into V_FATURA FROM tab_define where cd_chave_linha = 
                          V_chave_linha;
	        IF NOT FOUND THEN
		   SELECT 15 into V_FATURA from tab_define WHERE cd_chave_produto =
                             V_chave_produto;  
                   IF NOT FOUND THEN
                      V_FATURA := 0;
                   END IF;       
                END IF;
             END IF;
	  END IF;
       END IF;
   END LOOP;
END IF;

  IF V_FATURA > 0 THEN
     V_RESULTADO := 'DEF';
  END IF;

  IF V_FATURA = 15 AND NEW.fl_modovenda = ' 6' THEN
     V_FATURA := 77;
  END IF;

  IF NEW.cd_divisao in (1,51) THEN
     SELECT vl_saldo1 INTO V_SALDORESERVA from reserva_define 
            WHERE sg_loja = V_LOJA_CENTRAL;
  ELSIF NEW.cd_divisao in (2,52) THEN
     SELECT vl_saldo2 INTO V_SALDORESERVA from reserva_define 
            WHERE sg_loja = V_LOJA_CENTRAL;
  ELSE
     SELECT vl_saldo3 INTO V_SALDORESERVA from reserva_define 
            WHERE sg_loja = V_LOJA_CENTRAL;
  END IF;

  IF V_FATURA = 0 THEN
     IF NEW.fl_modovenda = ' 6' THEN 
        IF V_UF <> V_UF_Destino THEN 
           V_FATURA := 71;
           V_RESULTADO := '71-INTEST';
        ELSE
           IF V_SALDORESERVA >= V_SOITENSMINUTA THEN
              V_RESULTADO := '78-LOCAL';
	      V_FATURA := 78;
           ELSE
              V_RESULTADO := '77-LOCAL';
	      V_FATURA := 77;
	   END IF;
	END IF;
     ELSE 
        IF V_UF <> V_UF_Destino THEN 
           IF NEW.cd_divisao in (3,53) THEN
              IF (SELECT count(1) from minuta_item where cd_chave_min = V_CHAVEMIN
                        And cd_produto = 777777 limit 1) = 1 And 
	         (SELECT count(1) from minuta_item WHERE cd_chave_min = V_CHAVEMIN) = 1 THEN
                 V_FATURA := 1;  
                 V_RESULTADO := '1-DIV3-777777-INT';
              ELSE
                 V_FATURA := 15;
                 V_RESULTADO := '15-3-INTEST';
              END IF;
           ELSIF NEW.cd_divisao = 8 THEN
              V_FATURA := 28;
              V_RESULTADO := 'DIV=8-INT';
           ELSE
	      V_FATURA := 15;
              V_RESULTADO := '15-INTEST';
	   END IF;
		  
        ELSIF NEW.cd_divisao > 50 THEN
           IF NEW.cd_divisao in (3,53) THEN
              IF (SELECT count(1) from minuta_item where cd_chave_min = V_CHAVEMIN
                        And cd_produto = 777777 limit 1) = 1 And 
                 (SELECT count(1) from minuta_item WHERE cd_chave_min = V_CHAVEMIN) = 1 THEN
                 V_FATURA := 1;  
                 V_RESULTADO := '1-DIV3-777777';
              ELSE
                 V_RESULTADO := '15-DIV>50';
                 V_FATURA := 15;
              END IF;
           ELSIF NEW.cd_divisao = 58 THEN
              V_FATURA := 28;
              V_RESULTADO := '28-DIV=58';
           ELSE
	      V_FATURA := 15;
              V_RESULTADO := '15-DIV=51,52';
	   END IF;
	ELSIF V_tem_ST = '6' THEN
           IF NEW.fl_modovenda = ' 6' THEN
              V_FATURA := 77;
              V_RESULTADO := '77-STB';
           ELSIF NEW.cd_divisao = 8 THEN
              V_FATURA := 28;
              V_RESULTADO := '28-STB';
           ELSIF V_NFMANUAL = 'S' THEN
              V_FATURA := 1;
              V_RESULTADO := '1-STB';
           ELSIF NEW.cd_divisao = 1 AND
                 NEW.qt_prestacao2 = 0 AND
                 NEW.vl_complemento = 0 AND
                 NEW.vl_despfin > 0 AND
                 V_NOTFIN13 = 'S' AND
                 (COALESCE(NEW.dt_predatada,NEW.dt_minuta) - NEW.dt_minuta) < 11 THEN
              V_FATURA := 13;
              V_RESULTADO := '13-STB';
           ELSE
              V_FATURA := 15;
              V_RESULTADO := '15-STB';
           END IF;
	ELSIF V_tem_ST = ' ' THEN
           IF NEW.fl_modovenda = ' 6' THEN
              IF V_SALDORESERVA >= V_SOITENSMINUTA THEN
                 V_FATURA := 78;
                 V_RESULTADO := '78-A';
              ELSE
                 V_FATURA := 77;
                 V_RESULTADO := '77-A';
              END IF;
           ELSIF NEW.cd_divisao = 8 THEN
              V_FATURA := 28;
              V_RESULTADO := '28-A';
           ELSIF V_NFMANUAL = 'S' THEN
              V_FATURA := 1;
              V_RESULTADO := '1-A';
           ELSIF NEW.cd_divisao = 1 AND
                 NEW.qt_prestacao2 = 0 AND
                 NEW.vl_complemento = 0 AND
                 NEW.vl_despfin > 0 AND
                 V_NOTFIN13 = 'S' AND
                 (COALESCE(NEW.dt_predatada,NEW.dt_minuta) - NEW.dt_minuta) < 11 THEN
              V_FATURA := 13;
              V_RESULTADO := '13-A';
           ELSIF NEW.cd_divisao = 3 THEN
              IF V_SALDORESERVA >= V_SOITENSMINUTA THEN
                 V_FATURA := 16;
              ELSIF (SELECT count(1) from minuta_item where cd_chave_min = V_CHAVEMIN
                        And cd_produto = 777777 limit 1) = 1 And 
		 (SELECT count(1) from minuta_item WHERE cd_chave_min = V_CHAVEMIN) = 1 THEN
                 V_FATURA := 1;  
                 V_RESULTADO := '1-DIV-3-AB';
              ELSE
                 V_FATURA := 15;
                 V_RESULTADO := '15-AB';
              END IF;
           ELSIF NEW.cd_divisao = 2 THEN
              IF V_SALDORESERVA >= V_SOITENSMINUTA THEN
                 V_FATURA := 16;
                 V_RESULTADO := '16-A-DIV=2';
              ELSE
                 V_FATURA := 15;
                 V_RESULTADO := '15-S-SALDO-DIV=2';
              END IF;
           ELSE
              IF V_SALDORESERVA >= V_SOITENSMINUTA THEN
                 V_FATURA := 16;
                 V_RESULTADO := '16-A-DIV=1';
                 --raise notice ' 001-FIN: %',V_FATURA;
              ELSE
                 /*
                 O valor da DF deve ser igual ou superior ao valor medio das prestacoes" para que seja selecionado o faturamento "SL"
                 */
                 IF V_PROFCLIENTE = 'N' OR 
                 (NEW.VL_DESPFIN < (NEW.VL_CONTRATO / (NEW.QT_PRESTACAO1 + NEW.QT_PRESTACAO2 + V_PREDATADA))) THEN
                 --IF V_PROFCLIENTE = 'N' THEN
                    V_FATURA := 15;
                    V_RESULTADO := '15-S-SALDO-DIV1';
                 ELSE     -- ivanivan
                    V_FATURA := 3;
                    V_RESULTADO := '3-PROF=S';
                 END IF;
                 
                 
              END IF;
           END IF;
        END IF;
     END IF;
  ELSE
     IF NEW.fl_modovenda = ' 6' THEN
        IF V_UF <> V_UF_Destino THEN
           V_FATURA := 71;
           V_RESULTADO := '71-INTEST';
        ELSE
           V_FATURA := 77;
           V_RESULTADO := '77-EST';
        END IF;
     ELSE
        IF V_TPCLIENTE <> ' 1' THEN 
           IF NEW.cd_divisao = 8 THEN
              V_FATURA := 28;
              V_RESULTADO := '28-TPC<>1';
	   ELSIF NEW.fl_modovenda = ' 6' THEN
              V_FATURA := 71;
              V_RESULTADO := '71-TPC<>1';
           ELSIF NEW.cd_divisao in (3,53) THEN
              IF (SELECT count(1) from minuta_item where cd_chave_min = V_CHAVEMIN
                        And cd_produto = 777777 limit 1) = 1 And 
	         (SELECT count(1) from minuta_item WHERE cd_chave_min = V_CHAVEMIN) = 1 THEN
                 V_FATURA := 1;  
                 V_RESULTADO := '1-TPC<>1';
              ELSE
                 V_FATURA := 15;
                 V_RESULTADO := '15-DIV=3.TPC<>1';
              END IF;
           ELSE
              V_FATURA := 15;
              V_RESULTADO := '15-TPC<>1';
           END IF;
	ELSIF V_UF <> V_UF_Destino THEN
           IF NEW.cd_divisao in (3,53) THEN
              IF (SELECT count(1) from minuta_item where cd_chave_min = V_CHAVEMIN
                        And cd_produto = 777777 limit 1) = 1 And 
		 (SELECT count(1) from minuta_item WHERE cd_chave_min = V_CHAVEMIN) = 1 THEN
                 V_FATURA := 1;  
                 V_RESULTADO := '1-DIV3-INTEST';
              ELSE
                 V_FATURA := 15;
                 V_RESULTADO := '15-DIV3-INTEST';
              END IF;
           ELSIF NEW.cd_divisao = 8 THEN
              V_FATURA := 28;
              V_RESULTADO := '28-INTEST';
           ELSE
	      V_FATURA := 15;
              V_RESULTADO := '15-INTEST';
	   END IF;
	ELSIF NEW.cd_divisao > 50 THEN
           IF NEW.cd_divisao in (3,53) THEN
              IF (SELECT count(1) from minuta_item where cd_chave_min = V_CHAVEMIN
                        And cd_produto = 777777 limit 1) = 1 And 
		 (SELECT count(1) from minuta_item WHERE cd_chave_min = V_CHAVEMIN) = 1 THEN
                 V_FATURA := 1;  
                 V_RESULTADO := '1-DIV3-FATEST';
              ELSE
                 V_FATURA := 15;
                 V_RESULTADO := '15-FATEST';
              END IF;
           ELSIF NEW.cd_divisao = 8 THEN
              V_FATURA := 28;
              V_RESULTADO := '28-FATEST';
           ELSE
	      V_FATURA := 15;
              V_RESULTADO := '15-FATEST';
	   END IF;
	ELSIF V_tem_ST = '6' THEN
           IF NEW.fl_modovenda = ' 6' THEN
              V_FATURA := 77;
              V_RESULTADO := '77-X-STB';
           ELSIF NEW.cd_divisao = 8 THEN
              V_FATURA := 28;
              V_RESULTADO := '28-X-STB';
           ELSIF V_NFMANUAL = 'S' THEN
              V_FATURA := 1;
              V_RESULTADO := '1-X-STB';
           ELSIF NEW.cd_divisao = 1 AND
                 NEW.qt_prestacao2 = 0 AND
                 NEW.vl_complemento = 0 AND
                 NEW.vl_despfin > 0 AND
                 V_NOTFIN13 = 'S' AND
                 (COALESCE(NEW.dt_predatada,NEW.dt_minuta) - NEW.dt_minuta) < 11 THEN
              V_FATURA := 13;
              V_RESULTADO := '13-X-STB';
           ELSE
              V_FATURA := 15;
              V_RESULTADO := '15-X-STB';
           END IF;
	ELSIF V_tem_ST = ' ' THEN
           IF NEW.fl_modovenda = ' 6' THEN
              V_FATURA := 77;
              V_RESULTADO := '77-X-N-STB';
           ELSIF NEW.cd_divisao = 8 THEN
              V_RESULTADO := '28-X-N-STB';
              V_FATURA := 28;
           ELSIF V_NFMANUAL = 'S' THEN
              V_FATURA := 1;
              V_RESULTADO := '1-X-N-STB';
           ELSIF NEW.cd_divisao = 1 AND
                 NEW.qt_prestacao2 = 0 AND
                 NEW.vl_complemento = 0 AND
                 NEW.vl_despfin > 0 AND
                 V_NOTFIN13 = 'S' AND
                 (COALESCE(NEW.dt_predatada,NEW.dt_minuta) - NEW.dt_minuta) < 11 THEN
              V_FATURA := 13;
              V_RESULTADO := '13-X-N-STB';
           ELSIF NEW.cd_divisao = 3 THEN
              IF (SELECT count(1) from minuta_item where cd_chave_min = V_CHAVEMIN
                        And cd_produto = 777777 limit 1) = 1 And 
		 (SELECT count(1) from minuta_item WHERE cd_chave_min = V_CHAVEMIN) = 1 THEN
                 V_FATURA := 1;  
                 V_RESULTADO := '1-X3-N-STB';
              ELSE
                 V_FATURA := 15;
                 V_RESULTADO := '15-X1-N-STB';
              END IF;
           ELSIF NEW.cd_divisao = 2 THEN
              V_FATURA := 15;
              V_RESULTADO := '15-X2-N-STB';
           ELSE
              /*
              O valor da DF deve ser igual ou superior ao valor medio das prestacoes" para que seja selecionado o faturamento "SL"
              */
              IF V_PROFCLIENTE = 'N' OR 
                 (NEW.VL_DESPFIN < (NEW.VL_CONTRATO / (NEW.QT_PRESTACAO1 + NEW.QT_PRESTACAO2 + V_PREDATADA))) THEN
              --IF V_PROFCLIENTE = 'N' THEN
                 V_FATURA := 15;
                 V_RESULTADO := '15-PROF=N';
              ELSE
                 V_FATURA := 3; --ivanivan
                 V_RESULTADO := '3-PROF=S';
              END IF;
           END IF;
 	END IF;
     END IF;
  END IF;
     
  IF (SELECT count(1) FROM reserva_define WHERE sg_loja = V_LOJA_CENTRAL) = 0 THEN
     INSERT into reserva_define(sg_loja,vl_saldo1,vl_saldo2,vl_saldo3,vl_saldo4) 
           VALUES(V_LOJA_CENTRAL,0,0,0,0);
  END IF;

  IF V_FATURA Not In (16,78) THEN
     IF V_PCRESERVA > 0 THEN
        IF NEW.cd_divisao in (1,51) THEN
           UPDATE reserva_define set vl_saldo1 = vl_saldo1 + 
                (V_SOITENSMINUTA * (V_PCRESERVA / 100.0000)) WHERE sg_loja = V_LOJA_CENTRAL;
        ELSIF NEW.cd_divisao in (2,52) THEN
           UPDATE reserva_define set vl_saldo2 = vl_saldo2 + 
                (V_SOITENSMINUTA * (V_PCRESERVA / 100.0000)) WHERE sg_loja = V_LOJA_CENTRAL;
        ELSE
           UPDATE reserva_define set vl_saldo3 = vl_saldo3 + 
                (V_SOITENSMINUTA * (V_PCRESERVA / 100.0000)) WHERE sg_loja = V_LOJA_CENTRAL;
        END IF;
     END IF;
  ELSE
     IF NEW.cd_divisao in (1,51) THEN
        UPDATE reserva_define set vl_saldo1 = vl_saldo1 - V_SOITENSMINUTA
             WHERE sg_loja = V_LOJA_CENTRAL;
     ELSIF NEW.cd_divisao in (2,52) THEN
        UPDATE reserva_define set vl_saldo2 = vl_saldo2 - V_SOITENSMINUTA
             WHERE sg_loja = V_LOJA_CENTRAL;
     ELSE
        UPDATE reserva_define set vl_saldo3 = vl_saldo3 - V_SOITENSMINUTA
             WHERE sg_loja = V_LOJA_CENTRAL;
     END IF;
  END IF;

  
  
  
  
  
  NEW.tp_financeiro := V_FATURA;
  NEW.Cd_Chave_Con  := ( NEW.Sg_Loja || LPAD(NEW.tp_contrato::text, 2) || 
     LPAD(NEW.tp_financeiro::text, 2) || LPAD(NEW.nr_contrato::text, 8) );
  IF V_FATURA = 78 THEN
     NEW.cd_modo1 := 'B';
  END IF;
 
  RETURN NEW;
END
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
ALTER FUNCTION trigger_fct_trg_minuta_geral()
  OWNER TO usr_aplicacao;
