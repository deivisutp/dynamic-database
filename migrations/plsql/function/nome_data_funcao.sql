CREATE OR REPLACE FUNCTION nome_da_funcao (
    parametro_1 IN number,
    parametro_2 IN number
) 
RETURN number
IS
    -- Área de declaração de variáveis locais (opcional)
    v_variavel_local number;
BEGIN
    -- Corpo da função com a lógica de negócio
    v_variavel_local := parametro_1 + parametro_2;

    -- Retorno obrigatório do valor
    RETURN v_variavel_local;
    
EXCEPTION
    -- Tratamento de erros (opcional, mas altamente recomendado)
    WHEN OTHERS THEN
        RETURN NULL;
END nome_da_funcao;
/
