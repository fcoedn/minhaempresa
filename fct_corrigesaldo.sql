-- SELECT fct_corrigesaldo()
--select cd_chave,vl_saldo,fl_situacao,dt_caixa,qt_prest_pagas from  contrato where cd_chave_con='TED 777  107023'
--select * from saldodifere where fl_situacao='Q' limit 100

-- DROP FUNCTION fct_corrigesaldo();

CREATE OR REPLACE FUNCTION fct_corrigesaldo()
  RETURNS void AS
$BODY$
     DECLARE
        vl_saldocont     numeric(15,2);
        data_caixa        date;
        flag_situacao    varchar(1);
        qt_prestpagas numeric(2);
       	errosaldo          record;
   
  BEGIN
       --Cria temp para atualzar saldo no contrato
       drop table if exists saldoprest;
       create temp table saldoprest as
	   select cd_chave_con, sum(vl_saldo_crs) "vl_saldopre", max(dt_caixa)  "dt_caixa", 
	   '0'::varchar(1) fl_situacao, 0::numeric(15,2) vl_saldocon 
	   from prestacao group by cd_chave_con;
	   
       --Atualiza situacao, conforme contrato
       update saldoprest e set fl_situacao = case when e.vl_saldopre =0 then '6' 
              else c.fl_situacao end, vl_saldocon = c.vl_saldo
      	             from contrato c where e.cd_chave_con = c.cd_chave_con;

       --Gera tabela temp com os saldo diferentes (contrato x prestacao)
      drop table if exists saldodifere;
      create temp table saldodifere as 
	    select c.cd_chave_con, c.vl_saldo, e.vl_saldopre, e.dt_caixa, 
	    e.fl_situacao, e.vl_saldocon from contrato c 
	    join saldoprest e on c.cd_chave_con=e.cd_chave_con and 
	       c.vl_saldo <> e.vl_saldopre;
	       
-- QUANTIDADE DE PRESTAÇÕES PAGAS
      drop table if exists prettmp;

      create temp table prettmp as
             select prestacao.cd_chave_con,max(nr_prestacao) as qt_pagas
                from prestacao where prestacao.vl_saldo_crs = 0
                     group by prestacao.cd_chave_con ;

      CREATE INDEX IX_2 on prettmp (cd_chave_con);
      insert into saldodifere select c.cd_chave_con, c.vl_saldo,0,current_date,  
            'Q',0 from contrato c join prettmp p
            on c.cd_chave_con=p.cd_chave_con and 
            trim(c.qt_prest_pagas) <> trim(p.qt_pagas::varchar(2));
           
      --update contrato set qt_prest_pagas = prettmp.qt_pagas
      --from prettmp where
      --contrato.cd_chave_con = prettmp.cd_chave_con and
      --contrato.qt_prest_pagas <> prettmp.qt_pagas;

        --realiza um loop em todos os registros  da tabela
        FOR errosaldo in
            SELECT distinct on (cd_chave_con) saldodifere.* from saldodifere
   
        LOOP
           vl_saldocont := 0;
	   qt_prestpagas := 0;
           	   
           select  nr_prestacao into qt_prestpagas from prestacao 
                  WHERE cd_chave_con = errosaldo.cd_chave_con AND
            dt_caixa = (select max(dt_caixa) from prestacao 
                   where cd_chave_con  = errosaldo.cd_chave_con) 
                   order by nr_prestacao desc limit 1;
                        
                        
          --SELECT nr_prestacao into qt_prest_pagas from prestacao
          --WHERE cd_chave_con = baixa.cd_chave_con AND
          --   dt_caixa = (SELECT max(dt_caixa) from prestacao_card
          --         WHERE cd_chave_con = baixa.cd_chave_con) order by nr_prestacao desc 
           --        limit 1;


           flag_situacao := errosaldo.fl_situacao;
	   vl_saldocont  := errosaldo.vl_saldopre;
	   data_caixa    := errosaldo.dt_caixa;

           if vl_saldocont > 0 then
               data_caixa := NULL;
           end if;

           if errosaldo.vl_saldocon <> errosaldo.vl_saldopre or
              errosaldo.fl_situacao = 'Q'
              then
              insert into loggeral (cd_programa, dt_loggeral,ho_loggeral, 
                       sg_loja, pr_id,  cd_idreg,  tx_workpath,   tx_acao)
                   values('CORRIGESALDO',current_date,to_char(localtime,'hhmmss'),
                       'DTI',0,0,'function',errosaldo.cd_chave_con || ' : ' ||
                        errosaldo.vl_saldopre || ' x ' || errosaldo.vl_saldocon ||
                          ' : ' || qt_prestpagas ); 
               IF flag_situacao = 'Q' THEN
                  SELECT sum(vl_saldo_crs) into vl_saldocont from
                          prestacao where cd_chave_con = errosaldo.cd_chave_con;
                  IF FOUND THEN
                     IF vl_saldocont > 0 THEN
                        flag_situacao := '0';
                        data_caixa    := NULL;
                     ELSE
                        flag_situacao := '6';
                        SELECT max(dt_caixa) into data_caixa from  
                               prestacao where cd_chave_con = errosaldo.cd_chave_con;
                     END IF;
                  ELSE
                     vl_saldocont  := 0;
                     flag_situacao := '6';
                  END IF;
                  UPDATE contrato set vl_saldo    = vl_saldocont,
                                   qt_prest_pagas = qt_prestpagas,
                                   dt_caixa       = data_caixa,
                                   fl_situacao    = flag_situacao 
                           where cd_chave_con = errosaldo.cd_chave_con;
               ELSE
                  UPDATE contrato set vl_saldo    = vl_saldocont,
                                   qt_prest_pagas = qt_prestpagas,
                                   dt_caixa       = data_caixa,
                                   fl_situacao    = flag_situacao 
                           where cd_chave_con = errosaldo.cd_chave_con;
               END IF;
           end if;
            
     END LOOP;
      RETURN;
     END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
ALTER FUNCTION fct_corrigesaldo()
  OWNER TO usr_aplicacao;
