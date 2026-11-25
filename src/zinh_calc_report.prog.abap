*&---------------------------------------------------------------------*
*& Report ZINH_CALC_REPORT
*&---------------------------------------------------------------------*
*& In-house production time - standard values per work center
*&
*& Lists production order operations by plant, work center and order.
*& For every work center the standard value key (CRHD-VGWTS) is read
*& and its parameters (TC21-PAR01..PAR06) become dynamic ALV columns.
*& The column header is the parameter keyword (TC20T-TXT, e.g. Setup,
*& Machine, Labor) - the same text shown on the order operation screen.
*& The column content is the standard value of the order operation
*& (AFVV-VGW01..VGW06) with its unit (AFVV-VGE01..VGE06).
*&---------------------------------------------------------------------*
REPORT zinh_calc_report.

DATA: gv_werks TYPE aufk-werks,
      gv_arbpl TYPE crhd-arbpl,
      gv_aufnr TYPE aufk-aufnr.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME.
  SELECT-OPTIONS: s_werks FOR gv_werks,
                  s_arbpl FOR gv_arbpl,
                  s_aufnr FOR gv_aufnr.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-b02.
  PARAMETERS: p_rel RADIOBUTTON GROUP stat DEFAULT 'X',  " only released
              p_all RADIOBUTTON GROUP stat.              " created + released
SELECTION-SCREEN END OF BLOCK b2.

*----------------------------------------------------------------------*
CLASS lcl_report DEFINITION FINAL.
  PUBLIC SECTION.
    METHODS run.

  PRIVATE SECTION.
    CONSTANTS: gc_autyp_prod TYPE aufk-autyp VALUE '10',  " production order
               gc_max_par    TYPE i          VALUE 6,     " PAR01..PAR06
               gc_stat_crtd  TYPE j_status   VALUE 'I0001',
               gc_stat_rel   TYPE j_status   VALUE 'I0002',
               gc_stat_teco  TYPE j_status   VALUE 'I0045',
               gc_stat_clsd  TYPE j_status   VALUE 'I0046',
               gc_stat_dlfl  TYPE j_status   VALUE 'I0076'.

    TYPES: BEGIN OF ty_op,
             werks TYPE aufk-werks,
             arbpl TYPE crhd-arbpl,
             vgwts TYPE crhd-vgwts,
             aufnr TYPE aufk-aufnr,
             matnr TYPE afko-plnbez,
             gamng TYPE afko-gamng,
             gmein TYPE afko-gmein,
             vornr TYPE afvc-vornr,
             ltxa1 TYPE afvc-ltxa1,
             bmsch TYPE afvv-bmsch,
             meinh TYPE afvv-meinh,
             vgw01 TYPE afvv-vgw01,
             vgw02 TYPE afvv-vgw02,
             vgw03 TYPE afvv-vgw03,
             vgw04 TYPE afvv-vgw04,
             vgw05 TYPE afvv-vgw05,
             vgw06 TYPE afvv-vgw06,
             vge01 TYPE afvv-vge01,
             vge02 TYPE afvv-vge02,
             vge03 TYPE afvv-vge03,
             vge04 TYPE afvv-vge04,
             vge05 TYPE afvv-vge05,
             vge06 TYPE afvv-vge06,
           END OF ty_op,
           tt_op TYPE STANDARD TABLE OF ty_op WITH EMPTY KEY,

           BEGIN OF ty_param,
             parid    TYPE tc20-parid,
             txt      TYPE tc20t-txt,
             txtlg    TYPE tc20t-txtlg,
             col_val  TYPE lvc_fname,
             col_unit TYPE lvc_fname,
           END OF ty_param,
           tt_param TYPE STANDARD TABLE OF ty_param WITH EMPTY KEY.

    DATA: mt_op    TYPE tt_op,
          mt_tc21  TYPE SORTED TABLE OF tc21 WITH UNIQUE KEY vgwts,
          mt_param TYPE tt_param,
          mr_out   TYPE REF TO data.

    METHODS select_operations.
    METHODS read_parameters.
    METHODS build_output_table.
    METHODS fill_output_table.
    METHODS display.
    METHODS add_comp
      IMPORTING iv_name TYPE string
                iv_ddic TYPE string
      CHANGING  ct_comp TYPE cl_abap_structdescr=>component_table.
ENDCLASS.

*----------------------------------------------------------------------*
CLASS lcl_report IMPLEMENTATION.

  METHOD run.
    select_operations( ).
    IF mt_op IS INITIAL.
      MESSAGE 'No production order operations found for the selection'
        TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    read_parameters( ).
    build_output_table( ).
    fill_output_table( ).
    display( ).
  ENDMETHOD.


  METHOD select_operations.
    DATA: lt_stat_incl TYPE RANGE OF j_status,
          lt_stat_excl TYPE RANGE OF j_status.

    " Order status filter (system status, JEST):
    "   P_REL: REL active
    "   P_ALL: CRTD or REL active
    " Technically completed, closed and deletion-flagged orders are
    " always excluded.
    lt_stat_incl = VALUE #( sign = 'I' option = 'EQ' ( low = gc_stat_rel ) ).
    IF p_all = abap_true.
      APPEND VALUE #( sign = 'I' option = 'EQ' low = gc_stat_crtd ) TO lt_stat_incl.
    ENDIF.
    lt_stat_excl = VALUE #( sign = 'I' option = 'EQ'
                            ( low = gc_stat_teco )
                            ( low = gc_stat_clsd )
                            ( low = gc_stat_dlfl ) ).

    " Main operations (no sub-operations) of production orders
    SELECT k~werks,
           h~arbpl,
           h~vgwts,
           k~aufnr,
           f~plnbez AS matnr,
           f~gamng,
           f~gmein,
           c~vornr,
           c~ltxa1,
           v~bmsch,
           v~meinh,
           v~vgw01, v~vgw02, v~vgw03, v~vgw04, v~vgw05, v~vgw06,
           v~vge01, v~vge02, v~vge03, v~vge04, v~vge05, v~vge06
      FROM aufk AS k
      INNER JOIN afko AS f ON f~aufnr = k~aufnr
      INNER JOIN afvc AS c ON c~aufpl = f~aufpl
      INNER JOIN afvv AS v ON v~aufpl = c~aufpl
                          AND v~aplzl = c~aplzl
      INNER JOIN crhd AS h ON h~objid = c~arbid
                          AND h~objty = 'A'
      INTO CORRESPONDING FIELDS OF TABLE @mt_op
      WHERE k~werks IN @s_werks
        AND k~aufnr IN @s_aufnr
        AND k~autyp =  @gc_autyp_prod
        AND h~arbpl IN @s_arbpl
        AND c~sumnr =  '00000000'
        AND EXISTS ( SELECT objnr FROM jest
                       WHERE objnr =  k~objnr
                         AND stat  IN @lt_stat_incl
                         AND inact =  @space )
        AND NOT EXISTS ( SELECT objnr FROM jest
                           WHERE objnr =  k~objnr
                             AND stat  IN @lt_stat_excl
                             AND inact =  @space ).

    SORT mt_op BY werks arbpl aufnr vornr.
  ENDMETHOD.


  METHOD read_parameters.
    " Standard value keys of the selected work centers
    SELECT * FROM tc21
      INTO TABLE @mt_tc21
      FOR ALL ENTRIES IN @mt_op
      WHERE vgwts = @mt_op-vgwts.

    " Collect the distinct parameters in the order they are defined
    LOOP AT mt_tc21 ASSIGNING FIELD-SYMBOL(<ls_key>).
      DO gc_max_par TIMES.
        DATA(lv_pos) = sy-index.
        ASSIGN COMPONENT |PAR0{ lv_pos }| OF STRUCTURE <ls_key>
          TO FIELD-SYMBOL(<lv_parid>).
        IF sy-subrc <> 0 OR <lv_parid> IS INITIAL.
          CONTINUE.
        ENDIF.
        IF line_exists( mt_param[ parid = <lv_parid> ] ).
          CONTINUE.
        ENDIF.
        DATA(lv_idx) = lines( mt_param ) + 1.
        APPEND VALUE #(
          parid    = <lv_parid>
          col_val  = |P{ lv_idx WIDTH = 2 ALIGN = RIGHT PAD = '0' }_VAL|
          col_unit = |P{ lv_idx WIDTH = 2 ALIGN = RIGHT PAD = '0' }_UNIT| )
          TO mt_param.
      ENDDO.
    ENDLOOP.

    IF mt_param IS INITIAL.
      RETURN.
    ENDIF.

    " Keywords of the parameters (as shown on the operation screen)
    SELECT parid, txt, txtlg FROM tc20t
      INTO TABLE @DATA(lt_txt)
      FOR ALL ENTRIES IN @mt_param
      WHERE spras = @sy-langu
        AND parid = @mt_param-parid.

    LOOP AT mt_param ASSIGNING FIELD-SYMBOL(<ls_param>).
      READ TABLE lt_txt ASSIGNING FIELD-SYMBOL(<ls_txt>)
        WITH KEY parid = <ls_param>-parid.
      IF sy-subrc = 0.
        <ls_param>-txt   = <ls_txt>-txt.
        <ls_param>-txtlg = <ls_txt>-txtlg.
      ENDIF.
      IF <ls_param>-txt IS INITIAL.
        <ls_param>-txt = <ls_param>-parid.
      ENDIF.
      IF <ls_param>-txtlg IS INITIAL.
        <ls_param>-txtlg = <ls_param>-txt.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD build_output_table.
    DATA lt_comp TYPE cl_abap_structdescr=>component_table.

    " Fixed columns - names match TY_OP for MOVE-CORRESPONDING
    add_comp( EXPORTING iv_name = 'WERKS' iv_ddic = 'AUFK-WERKS'  CHANGING ct_comp = lt_comp ).
    add_comp( EXPORTING iv_name = 'ARBPL' iv_ddic = 'CRHD-ARBPL'  CHANGING ct_comp = lt_comp ).
    add_comp( EXPORTING iv_name = 'VGWTS' iv_ddic = 'CRHD-VGWTS'  CHANGING ct_comp = lt_comp ).
    add_comp( EXPORTING iv_name = 'AUFNR' iv_ddic = 'AUFK-AUFNR'  CHANGING ct_comp = lt_comp ).
    add_comp( EXPORTING iv_name = 'MATNR' iv_ddic = 'AFKO-PLNBEZ' CHANGING ct_comp = lt_comp ).
    add_comp( EXPORTING iv_name = 'GAMNG' iv_ddic = 'AFKO-GAMNG'  CHANGING ct_comp = lt_comp ).
    add_comp( EXPORTING iv_name = 'GMEIN' iv_ddic = 'AFKO-GMEIN'  CHANGING ct_comp = lt_comp ).
    add_comp( EXPORTING iv_name = 'VORNR' iv_ddic = 'AFVC-VORNR'  CHANGING ct_comp = lt_comp ).
    add_comp( EXPORTING iv_name = 'LTXA1' iv_ddic = 'AFVC-LTXA1'  CHANGING ct_comp = lt_comp ).
    add_comp( EXPORTING iv_name = 'BMSCH' iv_ddic = 'AFVV-BMSCH'  CHANGING ct_comp = lt_comp ).
    add_comp( EXPORTING iv_name = 'MEINH' iv_ddic = 'AFVV-MEINH'  CHANGING ct_comp = lt_comp ).

    " One value column + one unit column per standard value parameter
    LOOP AT mt_param ASSIGNING FIELD-SYMBOL(<ls_param>).
      add_comp( EXPORTING iv_name = CONV #( <ls_param>-col_val )
                          iv_ddic = 'AFVV-VGW01'
                CHANGING  ct_comp = lt_comp ).
      add_comp( EXPORTING iv_name = CONV #( <ls_param>-col_unit )
                          iv_ddic = 'AFVV-VGE01'
                CHANGING  ct_comp = lt_comp ).
    ENDLOOP.

    DATA(lo_struct) = cl_abap_structdescr=>create( lt_comp ).
    DATA(lo_table)  = cl_abap_tabledescr=>create( lo_struct ).
    CREATE DATA mr_out TYPE HANDLE lo_table.
  ENDMETHOD.


  METHOD add_comp.
    APPEND VALUE #(
      name = iv_name
      type = CAST cl_abap_datadescr(
               cl_abap_typedescr=>describe_by_name( iv_ddic ) ) )
      TO ct_comp.
  ENDMETHOD.


  METHOD fill_output_table.
    FIELD-SYMBOLS <lt_out> TYPE STANDARD TABLE.
    ASSIGN mr_out->* TO <lt_out>.

    LOOP AT mt_op ASSIGNING FIELD-SYMBOL(<ls_op>).
      APPEND INITIAL LINE TO <lt_out> ASSIGNING FIELD-SYMBOL(<ls_out>).
      MOVE-CORRESPONDING <ls_op> TO <ls_out>.

      READ TABLE mt_tc21 ASSIGNING FIELD-SYMBOL(<ls_key>)
        WITH TABLE KEY vgwts = <ls_op>-vgwts.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.

      " Position n of the key (PARnn) holds the value in VGWnn / VGEnn
      DO gc_max_par TIMES.
        DATA(lv_pos) = sy-index.
        ASSIGN COMPONENT |PAR0{ lv_pos }| OF STRUCTURE <ls_key>
          TO FIELD-SYMBOL(<lv_parid>).
        IF sy-subrc <> 0 OR <lv_parid> IS INITIAL.
          CONTINUE.
        ENDIF.

        READ TABLE mt_param ASSIGNING FIELD-SYMBOL(<ls_param>)
          WITH KEY parid = <lv_parid>.
        IF sy-subrc <> 0.
          CONTINUE.
        ENDIF.

        ASSIGN COMPONENT |VGW0{ lv_pos }| OF STRUCTURE <ls_op>
          TO FIELD-SYMBOL(<lv_val>).
        ASSIGN COMPONENT |VGE0{ lv_pos }| OF STRUCTURE <ls_op>
          TO FIELD-SYMBOL(<lv_unit>).
        ASSIGN COMPONENT <ls_param>-col_val OF STRUCTURE <ls_out>
          TO FIELD-SYMBOL(<lv_out_val>).
        ASSIGN COMPONENT <ls_param>-col_unit OF STRUCTURE <ls_out>
          TO FIELD-SYMBOL(<lv_out_unit>).

        IF <lv_val> IS ASSIGNED AND <lv_out_val> IS ASSIGNED.
          <lv_out_val> = <lv_val>.
        ENDIF.
        IF <lv_unit> IS ASSIGNED AND <lv_out_unit> IS ASSIGNED.
          <lv_out_unit> = <lv_unit>.
        ENDIF.
        UNASSIGN: <lv_val>, <lv_unit>, <lv_out_val>, <lv_out_unit>.
      ENDDO.
    ENDLOOP.
  ENDMETHOD.


  METHOD display.
    FIELD-SYMBOLS <lt_out> TYPE STANDARD TABLE.
    ASSIGN mr_out->* TO <lt_out>.

    TRY.
        cl_salv_table=>factory(
          IMPORTING r_salv_table = DATA(lo_alv)
          CHANGING  t_table      = <lt_out> ).

        lo_alv->get_functions( )->set_all( abap_true ).
        lo_alv->get_display_settings( )->set_striped_pattern( abap_true ).
        lo_alv->get_display_settings( )->set_list_header(
          'In-house production time - standard values per work center' ).

        DATA(lo_layout) = lo_alv->get_layout( ).
        lo_layout->set_key( VALUE #( report = sy-repid ) ).
        lo_layout->set_save_restriction( if_salv_c_layout=>restrict_none ).

        DATA(lo_columns) = lo_alv->get_columns( ).
        lo_columns->set_optimize( abap_true ).

        CAST cl_salv_column_table( lo_columns->get_column( 'GAMNG' )
          )->set_quantity_column( 'GMEIN' ).
        CAST cl_salv_column_table( lo_columns->get_column( 'BMSCH' )
          )->set_quantity_column( 'MEINH' ).

        " Dynamic columns: header = parameter keyword (Setup, Machine, ...)
        LOOP AT mt_param ASSIGNING FIELD-SYMBOL(<ls_param>).
          DATA(lo_col) = CAST cl_salv_column_table(
                           lo_columns->get_column( <ls_param>-col_val ) ).
          lo_col->set_short_text(  CONV #( <ls_param>-txt ) ).
          lo_col->set_medium_text( CONV #( <ls_param>-txtlg ) ).
          lo_col->set_long_text(   CONV #( <ls_param>-txtlg ) ).
          lo_col->set_quantity_column( <ls_param>-col_unit ).

          lo_col = CAST cl_salv_column_table(
                     lo_columns->get_column( <ls_param>-col_unit ) ).
          lo_col->set_short_text(  CONV #( |{ <ls_param>-txt } Un.| ) ).
          lo_col->set_medium_text( CONV #( |{ <ls_param>-txtlg } unit| ) ).
          lo_col->set_long_text(   CONV #( |{ <ls_param>-txtlg } unit| ) ).
        ENDLOOP.

        DATA(lo_sorts) = lo_alv->get_sorts( ).
        lo_sorts->add_sort( columnname = 'WERKS' ).
        lo_sorts->add_sort( columnname = 'ARBPL' ).
        lo_sorts->add_sort( columnname = 'AUFNR' ).
        lo_sorts->add_sort( columnname = 'VORNR' ).

        lo_alv->display( ).

      CATCH cx_salv_msg cx_salv_error INTO DATA(lx_salv).
        MESSAGE lx_salv->get_text( ) TYPE 'I' DISPLAY LIKE 'E'.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
START-OF-SELECTION.
  NEW lcl_report( )->run( ).
