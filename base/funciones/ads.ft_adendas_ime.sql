CREATE OR REPLACE FUNCTION ads.ft_adendas_ime (
  p_administrador integer,
  p_id_usuario integer,
  p_tabla varchar,
  p_transaccion varchar
)
RETURNS varchar AS
$body$
/**************************************************************************
 SISTEMA:		Adendas
 FUNCION: 		ads.ft_adendas_ime
 DESCRIPCION:   Función que gestiona las operaciones basicas (inserciones, modificaciones, eliminaciones de la tabla 'ads.tadendas'
 AUTOR: 		 (valvarado)
 FECHA:	        24-06-2019 15:15:06
 COMENTARIOS:
***************************************************************************
 HISTORIAL DE MODIFICACIONES:
#ISSUE				FECHA				AUTOR				DESCRIPCION
#
 ***************************************************************************/

DECLARE
    v_parametros           record;
    v_total_pago           decimal;
    v_resp                 varchar;
    v_nombre_funcion       varchar;
    v_id_adenda            integer;
    v_resp_doc             varchar;
    v_id_depto             integer;
    v_id_funcionario       integer;
    v_id_obligacion_pago   integer;
    v_num_tramite          varchar;
    v_id_proceso_wf        integer;
    v_id_estado_wf         integer;
    v_codigo_estado        varchar;
    v_obligacion_bloqueado boolean;
    v_obligacion           record;
    v_id_periodo           integer;
    v_num_adenda           varchar;
    v_bloquear_obligacion  boolean;
    v_estado               varchar;
    va_id_tipo_estado      integer[];
    va_codigo_estado       varchar[];
    va_disparador          varchar[];
    va_regla               varchar[];
    va_prioridad           integer[];
    v_num_estados          integer;
    v_obs                  varchar;
    v_id_estado_actual     integer;
    v_id_tipo_estado       integer;
BEGIN

    v_nombre_funcion = 'ads.ft_adendas_ime';
    v_parametros = pxp.f_get_record(p_tabla);

    if (p_transaccion = 'ADS_ADENDA_CLONAR') then

        begin

            v_num_tramite = ads.f_validar_existe_adenda(v_parametros.id_obligacion_pago);
            v_num_tramite = ads.f_validar_estado_op(v_parametros.id_obligacion_pago);
            v_obligacion_bloqueado = ads.f_validar_obligacion_pago_no_bloqueado(v_parametros.id_obligacion_pago);

            SELECT op.total_pago, sol.id_funcionario, sol.id_depto
            INTO v_total_pago, v_id_funcionario, v_id_depto
            FROM tes.tobligacion_pago op
                     INNER JOIN adq.tcotizacion cot ON cot.id_obligacion_pago = op.id_obligacion_pago
                     INNER JOIN adq.tproceso_compra pc ON pc.id_proceso_compra = cot.id_proceso_compra
                     INNER JOIN adq.tsolicitud sol ON sol.id_solicitud = pc.id_solicitud
            WHERE op.id_obligacion_pago = v_parametros.id_obligacion_pago;

            select id_periodo
            into v_id_periodo
            from param.tperiodo per
            where per.fecha_ini <= now()::date
              and per.fecha_fin >= now()::date
            limit 1
            offset
            0;

            v_num_adenda =
                    param.f_obtener_correlativo('C_ADS', v_id_periodo, NULL, v_id_depto, p_id_usuario, 'ADS', NULL);

            INSERT INTO ads.tadendas (id_usuario_reg,
                                      id_usuario_mod,
                                      fecha_reg,
                                      fecha_mod,
                                      estado_reg,
                                      id_usuario_ai,
                                      usuario_ai,
                                      id_obligacion_pago,
                                      id_funcionario,
                                      id_estado_wf,
                                      id_proceso_wf,
                                      estado,
                                      num_tramite,
                                      numero,
                                      total_pago,
                                      nueva_fecha_fin,
                                      observacion,
                                      id_contrato_adenda)
            VALUES (p_id_usuario,
                    NULL,
                    NOW(),
                    NULL,
                    'activo',
                    v_parametros._id_usuario_ai,
                    v_parametros._nombre_usuario_ai,
                    v_parametros.id_obligacion_pago,
                    v_id_funcionario,
                    NULL,
                    NULL,
                    NULL,
                    NULL,
                    v_num_adenda,
                    v_total_pago,
                    v_parametros.nueva_fecha_fin,
                    v_parametros.observacion,
                    v_parametros.id_contrato_adenda)
            RETURNING id_adenda into v_id_adenda;

            INSERT INTO ads.tadenda_det(id_usuario_reg,
                                        id_usuario_mod,
                                        fecha_reg,
                                        fecha_mod,
                                        estado_reg,
                                        id_usuario_ai,
                                        usuario_ai,
                                        id_obligacion_det,
                                        id_obligacion_pago,
                                        id_concepto_ingas,
                                        id_centro_costo,
                                        id_partida,
                                        id_partida_ejecucion_com,
                                        descripcion,
                                        monto_pago_mo,
                                        monto_pago_mb,
                                        factor_porcentual,
                                        id_orden_trabajo,
                                        monto_pago_sg_mo,
                                        monto_pago_sg_mb,
                                        id_adenda)
            SELECT id_usuario_reg,
                   id_usuario_mod,
                   fecha_reg,
                   fecha_mod,
                   estado_reg,
                   id_usuario_ai,
                   usuario_ai,
                   id_obligacion_det,
                   id_obligacion_pago,
                   id_concepto_ingas,
                   id_centro_costo,
                   id_partida,
                   id_partida_ejecucion_com,
                   descripcion,
                   monto_pago_mo,
                   monto_pago_mb,
                   factor_porcentual,
                   id_orden_trabajo,
                   monto_pago_sg_mo,
                   monto_pago_sg_mb,
                   v_id_adenda
            FROM tes.tobligacion_det
            WHERE id_obligacion_pago = v_parametros.id_obligacion_pago;

            select obp.num_tramite,
                   obp.id_proceso_wf,
                   obp.id_estado_wf
            into
                v_obligacion
            from tes.tobligacion_pago obp
            where obp.id_obligacion_pago = v_parametros.id_obligacion_pago;

            SELECT ps_id_proceso_wf,
                   ps_id_estado_wf,
                   ps_codigo_estado,
                   ps_nro_tramite
            into
                v_id_proceso_wf,v_id_estado_wf,v_codigo_estado, v_num_tramite
            FROM wf.f_registra_proceso_disparado_wf(
                    p_id_usuario,
                    v_parametros._id_usuario_ai,
                    v_parametros._nombre_usuario_ai,
                    v_obligacion.id_estado_wf,
                    v_id_funcionario,
                    v_id_depto,
                    'Registro Manual de Adendas',
                    'SEG-AD',
                    '');

            UPDATE ads.tadendas
            SET num_tramite   = v_num_tramite,
                id_proceso_wf = v_id_proceso_wf,
                id_estado_wf  = v_id_estado_wf,
                estado        = v_codigo_estado
            WHERE id_adenda = v_id_adenda;

            v_resp_doc = wf.f_inserta_documento_wf(p_id_usuario, v_id_proceso_wf, v_id_estado_wf);

            v_resp_doc = wf.f_verifica_documento(p_id_usuario, v_id_estado_wf);

            v_bloquear_obligacion = ads.f_bloquear_obligacion_pago(v_parametros.id_obligacion_pago, 1);
            v_bloquear_obligacion = ads.f_cambiar_pago_variable_op(v_parametros.id_obligacion_pago, 'si');

            v_resp = pxp.f_agrega_clave(v_resp, 'mensaje',
                                        'Sis Adendas almacenado(a) con exito (id_adenda' || v_id_adenda || ')');
            v_resp = pxp.f_agrega_clave(v_resp, 'id_adenda', v_id_adenda::varchar);

            return v_resp;

        end;

    elsif (p_transaccion = 'ADS_ADENDA_MOD') then

        begin

            update ads.tadendas
            set observacion        = v_parametros.observacion,
                id_usuario_ai      = v_parametros._id_usuario_ai,
                fecha_mod          = now(),
                id_usuario_mod     = p_id_usuario,
                nueva_fecha_fin    = v_parametros.nueva_fecha_fin,
                id_contrato_adenda = v_parametros.id_contrato_adenda,
                id_funcionario     = v_parametros.id_funcionario
            where id_adenda = v_parametros.id_adenda;

            v_resp = pxp.f_agrega_clave(v_resp, 'mensaje', 'Adenda modificada');
            v_resp = pxp.f_agrega_clave(v_resp, 'id_adenda', v_parametros.id_adenda::varchar);

            return v_resp;

        end;

    elsif (p_transaccion = 'ADS_ADENDA_ELI') then

        begin

            select ad.id_proceso_wf,
                   ad.id_estado_wf,
                   ad.estado,
                   ad.num_tramite,
                   op.id_depto,
                   op.id_obligacion_pago,
                   op.tipo_obligacion,
                   op.total_nro_cuota,
                   op.fecha_pp_ini,
                   op.rotacion,
                   op.id_plantilla,
                   op.tipo_cambio_conv,
                   pr.desc_proveedor,
                   op.pago_variable,
                   op.comprometido,
                   ad.id_usuario_reg,
                   op.fecha
            into
                v_id_proceso_wf,
                v_id_estado_wf,
                v_codigo_estado,
                v_num_tramite,
                v_id_depto,
                v_id_obligacion_pago
            from ads.tadendas ad
                     left join tes.tobligacion_pago op on op.id_obligacion_pago = ad.id_obligacion_pago
                     left join param.vproveedor pr on pr.id_proveedor = op.id_proveedor
            where ad.id_adenda = v_parametros.id_adenda;

            if v_codigo_estado = 'aprobado' then
                raise exception '%','No es posible anular una adenda en estado ' || v_codigo_estado;
            end if;

            select te.id_tipo_estado, te.codigo, ew.id_estado_wf
            into
                v_id_tipo_estado, v_codigo_estado, v_id_estado_wf
            from wf.tproceso_wf pw
                     inner join wf.ttipo_proceso tp on pw.id_tipo_proceso = tp.id_tipo_proceso
                     inner join wf.ttipo_estado te on te.id_tipo_proceso = tp.id_tipo_proceso and te.codigo = 'anulado'
                     inner join wf.testado_wf ew on ew.id_proceso_wf = pw.id_proceso_wf
            where pw.id_proceso_wf = v_id_proceso_wf;

            v_id_estado_actual = wf.f_registra_estado_wf(v_id_tipo_estado,
                                                         v_parametros.id_funcionario_wf,
                                                         v_id_estado_wf,
                                                         v_id_proceso_wf,
                                                         p_id_usuario,
                                                         v_parametros._id_usuario_ai,
                                                         v_parametros._nombre_usuario_ai,
                                                         null,
                                                         v_parametros.obs);

            update ads.tadendas
            set id_estado_wf   = v_id_estado_actual,
                estado         = v_codigo_estado,
                id_usuario_mod = p_id_usuario,
                fecha_mod      = now(),
                id_usuario_ai  = v_parametros._id_usuario_ai,
                usuario_ai     = v_parametros._nombre_usuario_ai
            where id_adenda = v_parametros.id_adenda;

            v_resp = ads.f_bloquear_obligacion_pago(v_id_obligacion_pago, 0)::varchar;

            v_resp = pxp.f_agrega_clave(v_resp, 'mensaje', 'La Adenda fue Anulada');
            v_resp = pxp.f_agrega_clave(v_resp, 'id_adenda', v_parametros.id_adenda::varchar);

            return v_resp;
        end;
    elsif (p_transaccion = 'ADS_ADENDA_SiGEST') then
        begin

            select ad.id_proceso_wf,
                   ad.id_estado_wf,
                   ad.estado,
                   ad.num_tramite,
                   op.id_depto,
                   op.id_obligacion_pago,
                   op.tipo_obligacion,
                   op.total_nro_cuota,
                   op.fecha_pp_ini,
                   op.rotacion,
                   op.id_plantilla,
                   op.tipo_cambio_conv,
                   pr.desc_proveedor,
                   op.pago_variable,
                   op.comprometido,
                   ad.id_usuario_reg,
                   op.fecha
            into
                v_id_proceso_wf,
                v_id_estado_wf,
                v_codigo_estado,
                v_num_tramite,
                v_id_depto,
                v_id_obligacion_pago
            from ads.tadendas ad
                     left join tes.tobligacion_pago op on op.id_obligacion_pago = ad.id_obligacion_pago
                     left join param.vproveedor pr on pr.id_proveedor = op.id_proveedor
            where ad.id_adenda = v_parametros.id_adenda;

            SELECT *
            into
                va_id_tipo_estado,
                va_codigo_estado,
                va_disparador,
                va_regla,
                va_prioridad
            FROM wf.f_obtener_estado_wf(v_id_proceso_wf, v_id_estado_wf, NULL, 'siguiente');
            v_num_estados = array_length(va_id_tipo_estado, 1);
            v_obs = '';

            if va_codigo_estado[1]::varchar = 'aprobado' then
                IF exists(select *
                          from ads.f_verificar_presupuesto() vp
                          where vp.disponible = 'false'
                            and vp.id_adenda = v_parametros.id_adenda) THEN
                    RAISE EXCEPTION 'No se tiene suficiente presupeusto para el tramite (%)', v_num_tramite;
                END IF;
                v_resp = ads.f_aprobar_adenda(v_parametros.id_adenda, p_id_usuario);
                v_resp = ads.f_confirmar_adenda(v_parametros.id_adenda);
                v_resp = ads.f_bloquear_obligacion_pago(v_id_obligacion_pago, 0)::varchar;
            end if;

            v_id_estado_actual = wf.f_registra_estado_wf(va_id_tipo_estado[1],
                                                         v_parametros.id_funcionario_wf,
                                                         v_id_estado_wf,
                                                         v_id_proceso_wf,
                                                         p_id_usuario,
                                                         v_parametros._id_usuario_ai,
                                                         v_parametros._nombre_usuario_ai,
                                                         null,
                                                         v_obs);

            update ads.tadendas
            set id_estado_wf   = v_id_estado_actual,
                estado         = va_codigo_estado[1],
                id_usuario_mod = p_id_usuario,
                fecha_mod      = now(),
                id_usuario_ai  = v_parametros._id_usuario_ai,
                usuario_ai     = v_parametros._nombre_usuario_ai
            where id_adenda = v_parametros.id_adenda;

            v_resp = pxp.f_agrega_clave(v_resp, 'mensaje', 'La obligación paso al siguiente estado');
            return v_resp;
        end;

    else
        raise exception 'Transaccion inexistente: %',p_transaccion;

    end if;

EXCEPTION

    WHEN OTHERS THEN
        v_resp = '';
        v_resp = pxp.f_agrega_clave(v_resp, 'mensaje', SQLERRM);
        v_resp = pxp.f_agrega_clave(v_resp, 'codigo_error', SQLSTATE);
        v_resp = pxp.f_agrega_clave(v_resp, 'procedimientos', v_nombre_funcion);
        raise exception '%',v_resp;

END;
$body$
LANGUAGE 'plpgsql'
VOLATILE
CALLED ON NULL INPUT
SECURITY INVOKER
COST 100;

ALTER FUNCTION ads.ft_adendas_ime (p_administrador integer, p_id_usuario integer, p_tabla varchar, p_transaccion varchar)
  OWNER TO postgres;