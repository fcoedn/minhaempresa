drop table if exists garantiadifal1;
create temp table garantiadifal1 as
select ite.sg_loja, ite.tp_minuta,ite.tp_fin, ite.nr_minuta,ite.nr_contrato,ite.dt_venda,ite.vl_preco_uni,ite.vl_pre_uni_urv,
       con.cd_chave_cli,ite.cd_chave,cli.no_cliente,ite.sg_loja || lpad(ite.nr_minuta::text,8,' ') || ite.nr_item as "cd_chave_min"
from contrato_item ite join contrato con 
on ite.cd_chave_con = con.cd_chave_con 
join cliente cli on con.cd_chave_cli = cli.cd_chave
 where ite.dt_venda between '2016-01-01' and '2016-05-31'
  and ite.vl_garantia > 0 and ite.vl_preco_uni <> ite.vl_pre_uni_urv 
  and con.dt_exclui is null and (con.dt_cancel is null or con.dt_cancel > '2016-12-31');

create index idx_difal1 on garantiadifal1(cd_chave_min);
create index idx_difal2 on garantiadifal1(cd_chave_cli);
create index idx_difal3 on garantiadifal1(cd_chave);

drop table if exists garantiadifal2;
create temp table garantiadifal2 as
   select ite.*, ' '::varchar(14) as nr_cpf, ' '::varchar(8) as cd_garantia
       from garantiadifal1 ite join minuta_item mite 
       on ite.cd_chave_min = mite.cd_chave where (ite.vl_preco_uni <> (ite.vl_pre_uni_urv + mite.vl_despfin));

update garantiadifal2 set nr_cpf = documento.nr_documento
        from documento where garantiadifal2.cd_chave_cli = documento.cd_chave_cli;
         
update garantiadifal2 set cd_garantia = aon_contrato.cd_codigo 
       from aon_contrato where garantiadifal2.cd_chave = aon_contrato.cd_chave_item;
       
 select sg_loja,nr_minuta,nr_contrato,dt_venda,no_cliente,nr_cpf,cd_garantia,vl_preco_uni,vl_pre_uni_urv from garantiadifal2;