# Para utilizar IEx.pry
require IEx

defmodule ServidorGV do
  @moduledoc """
      modulo del servicio de vistas
  """

  # Constantes
  @latidos_fallidos 4

  @intervalo_latidos 50

  # Tipo estructura de datos que guarda el estado del servidor de vistas
  # COMPLETAR  con lo campos necesarios para gestionar
  # el estado del gestor de vistas
  defstruct vista: %{num_vista: 0, primario: :undefined, copia: :undefined},
            tentativa: %{num_vista: 0, primario: :undefined, copia: :undefined},
            # lista que contien tuplas {nodo, numLatidos}
            resto_nodos: [],
            primario_latido: @latidos_fallidos + 1,
            copia_latido: @latidos_fallidos + 1

  # pepe = %ServidorGv{num_vista: 40}
  # pepe.num_vista = pepe.num_vas

  @doc """
      Acceso externo para constante de latidos fallidos
  """
  def latidos_fallidos() do
    @latidos_fallidos
  end

  @doc """
      acceso externo para constante intervalo latido
  """
  def intervalo_latidos() do
    @intervalo_latidos
  end

  @doc """
      Generar un estructura de datos vista inicial
  """
  def vista_inicial() do
    %ServidorGV{}
  end

  @doc """
      Poner en marcha el servidor para gestión de vistas
      Devolver atomo que referencia al nuevo nodo Elixir
  """
  @spec startNodo(String.t(), String.t()) :: node
  def startNodo(nombre, maquina) do
    # fichero en curso
    NodoRemoto.start(nombre, maquina, __ENV__.file)
  end

  @doc """
      Poner en marcha servicio trás esperar al pleno funcionamiento del nodo
  """
  @spec startService(node) :: boolean
  def startService(nodoElixir) do
    NodoRemoto.esperaNodoOperativo(nodoElixir, __MODULE__)

    # Poner en marcha el código del gestor de vistas
    Node.spawn(nodoElixir, __MODULE__, :init_sv, [])
  end

  # ------------------- FUNCIONES PRIVADAS ----------------------------------

  # Estas 2 primeras deben ser defs para llamadas tipo (MODULE, funcion,[])
  def init_sv() do
    Process.register(self(), :servidor_gv)

    # otro proceso concurrente
    spawn(__MODULE__, :init_monitor, [self()])

    #### VUESTRO CODIGO DE INICIALIZACION

    bucle_recepcion(%ServidorGV{})
  end

  def init_monitor(pid_principal) do
    send(pid_principal, :procesa_situacion_servidores)
    Process.sleep(@intervalo_latidos)
    init_monitor(pid_principal)
  end

  defp bucle_recepcion(estado_sistema) do
    estado =
      receive do
        {:latido, n_vista_latido, nodo_emisor} ->
          case estado_sistema.tentativa.num_vista do
            0 ->
              (IO.ANSI.blue() <> "No hay primario, inicializo") |> IO.puts()

              estado = %{
                estado_sistema
                | tentativa: %{
                    estado_sistema.tentativa
                    | num_vista: 1,
                      primario: nodo_emisor,
                      copia: :undefined
                  },
                  primario_latido: @latidos_fallidos + 1
              }

              # mando la vista pero no es valida por ahora
              send({:cliente_gv, nodo_emisor}, {:vista_tentativa, estado.tentativa, false})
              estado

            1 ->
              (IO.ANSI.blue() <> "Hay primario, no hay copia") |> IO.puts()

              cond do
                nodo_emisor == estado_sistema.tentativa.primario ->
                  # el que ha hecho latido es el primario
                  (IO.ANSI.green() <> "Tengo primario, y primario hace el latido de nuevo")
                  |> IO.puts()

                  # envio
                  send(
                    {:cliente_gv, nodo_emisor},
                    {:vista_tentativa, estado_sistema.tentativa, false}
                  )

                  # reinicio latidos ya qu sigue vivo
                  %{estado_sistema | primario_latido: @latidos_fallidos + 1}

                n_vista_latido == 0 ->
                  (IO.ANSI.green() <> "El nodo que hace latido es nuevo") |> IO.puts()

                  estado = %{
                    estado_sistema
                    | tentativa: %{
                        estado_sistema.tentativa
                        | num_vista: estado_sistema.tentativa.num_vista + 1,
                          copia: nodo_emisor
                      },
                      copia_latido: @latidos_fallidos + 1
                  }

                  send({:cliente_gv, nodo_emisor}, {:vista_tentativa, estado.tentativa, true})
                  ##################################
                  # valido???
                  %{estado | vista: estado.tentativa}

                ##################################
                true ->
                  (IO.ANSI.red() <>
                     "No deberia sacar este caso. \n Vista = 1, nodo: late con latido != 0 y no existe aun la copia" <>
                     IO.ANSI.reset())
                  |> IO.puts()
              end

            _ ->
              (IO.ANSI.blue() <> "Vista != 1 y 0" <> IO.ANSI.reset()) |> IO.puts()

              cond do
                nodo_emisor == estado_sistema.tentativa.primario ->
                  (IO.ANSI.pink() <> "PRIMARIO" <> IO.ANSI.reset()) |> IO.puts()

                  estadoNuevo =
                    cond do
                      n_vista_latido == estado_sistema.tentativa.num_vista ->
                        (IO.ANSI.green() <> "Primario confirma la vista") |> IO.puts()
                        # confirmo vista y reinicio los latidos
                        %{
                          estado_sistema
                          | vista: estado_sistema.tentativa,
                            primario_latido: @latidos_fallidos + 1
                        }

                      n_vista_latido == 0 ->
                        (IO.ANSI.red() <> "*********PRIMARIO CAIDO***********") |> IO.puts()
                        promocion(estado_sistema)

                      true ->
                        (IO.ANSI.green() <> "Primario vive") |> IO.puts()
                        %{estado_sistema | primario_latido: @latidos_fallidos + 1}
                    end

                  consistencia = estadoNuevo.tentativa == estadoNuevo.vista

                  send(
                    {:cliente_gv, nodo_emisor},
                    {:vista_tentativa, estadoNuevo.tentativa, consistencia}
                  )

                  estadoNuevo

                nodo_emisor == estado_sistema.tentativa.copia ->
                  (IO.ANSI.pink() <> "COPIA" <> IO.ANSI.reset()) |> IO.puts()

                  estadoNuevo =
                    cond do
                      n_vista_latido == 0 ->
                        (IO.ANSI.red() <> "*********COPIA CAIDO***********") |> IO.puts()
                        promocionCopia(estado_sistema)

                      true ->
                        %{estado_sistema | copia_latido: @latidos_fallidos + 1}
                    end

                  consistencia = estadoNuevo.tentativa == estadoNuevo.vista

                  send(
                    {:cliente_gv, nodo_emisor},
                    {:vista_tentativa, estadoNuevo.tentativa, consistencia}
                  )

                  estadoNuevo

                true ->
                  # Resto de casos
                  (IO.ANSI.pink() <> "NO PRIMARIO NO COPIA" <> IO.ANSI.reset()) |> IO.puts()

                  estadoNuevo =
                    if n_vista_latido == 0 do
                      (IO.ANSI.green() <> "Registro nodo como espera") |> IO.puts()

                      %{
                        estado_sistema
                        | resto_nodos:
                            estado_sistema.resto_nodos ++ [{nodo_emisor, @latidos_fallidos + 1}]
                      }
                    else
                      (IO.ANSI.green() <> "Actualizo nodo en espera pq sigue vivo") |> IO.puts()

                      nuevaListaNodos =
                        List.keyreplace?(
                          estado_sistema.resto_nodos,
                          nodo_emisor,
                          0,
                          {nodo_emisor, @latidos_fallidos + 1}
                        )

                      %{estado_sistema | resto_nodos: nuevaListaNodos}
                    end

                  consistencia = estadoNuevo.tentativa == estadoNuevo.vista

                  send(
                    {:cliente_gv, nodo_emisor},
                    {:vista_tentativa, estadoNuevo.tentativa, consistencia}
                  )

                  estadoNuevo
              end

            {:obten_vista_valida, pid} ->
              (IO.ANSI.blue() <> "ME PIDEN LA VISTA SIN MAS") |> IO.puts()
              consistencia = estado_sistema.tentativa == estado_sistema.vista
              send(pid, {:vista_tentativa, estado_sistema.tentativa, consistencia})
              estado_sistema

            :procesa_situacion_servidores ->
              #lista_nodos = estado_sistema.resto_nodos

              estado =
                if (length(estado_sistema.resto_nodos) > 0) do
                  #lista_nodos = for i <- lista_nodos, do: {elem(i, 0), elem(i, 1) - 1}
                  estado_sistema.resto_nodos = Map.map(estado_sistema.resto_nodos, fn {a,b} -> {a,b-1}, end)

                  lista_nodos = borrarInactivos(estado_sistema.resto_nodos)

                  estado_sistema = %{estado_sistema | resto_nodos: lista_nodos}

                  primarioInactivo = estado_sistema.primario_latido == 0
                  copiaInactivo = estado_sistema.copia_latido == 0

                  estadoNuevo =
                    cond do
                      primarioInactivo && copiaInactivo ->
                        (IO.ANSI.red() <> "##############PRIMARIO y COPIA CAIDO################")
                        |> IO.puts()

                        vista_inicial()

                      primarioInactivo ->
                        (IO.ANSI.pink() <> "### PRIMARIO CAIDO - COPIA VIVE ###") |> IO.puts()
                        promocion(estado_sistema)

                      copiaInactivo ->
                        (IO.ANSI.pink() <> "### COPIA CAIDO - PRIMARIO VIVE ###") |> IO.puts()
                        promocioncopia(estado_sistema)
                    end
                    estadoNuevo
                else
                    (IO.ANSI.red() <> "¬¬¬¬¬¬¬¬¬¬¬¬¬¬¬NO TENGO NODOS EN EPERA ") |> IO.puts()
                    estado_sistema
                end
            estado
        end

    bucle_recepcion(estado)
  end

  defmodule Prueba2 do
    def borrarInactivos([]) do
      []
    end

    def borrarInactivos(lista) do
      [uno | resto] = lista

      if elem(uno, 1) == 0 do
        borrarInactivos(resto)
      else
        [uno] ++ borrarInactivos(resto)
      end
    end
  end

  defp promocion(estado_sist) do
    (IO.ANSI.blue() <> "CREANDO NUEVO PRIMARIO") |> IO.puts()

    if estado_sist.tentativa == estado_sist.vista do
      %{
        estado_sist
        | tentativa: %{
            estado_sist.tentativa
            | primario: estado_sist.tentativa.copia,
              copia: :undefined,
              primario_latido: estado_sist.tentativa.copia_latido
          }
      }

      promocionCopia(estado_sist)
    else
      # CRASH
      (IO.ANSI.red() <> "##############PRIMARIO y COPIA CAIDO################") |> IO.puts()
      vista_inicial()
    end
  end

  defp promocionCopia(estado_sist) do
    (IO.ANSI.blue() <> "CREANDO NUEVA COPIA") |> IO.puts()

    estado =
      if estado.tentativa.primario != :undefined do
        len = length(resto_nodos)

        estadoNuevo =
          cond do
            len == 0 ->
              # no hay nodos esperando
              (IO.ANSI.green() <> "NO HAY NODOS PARA SUSTITUIR A COPIA") |> IO.puts()

              %{
                estado_sist
                | tentativa: %{
                    estado_sist.tentativa
                    | num_vista: estado_sist.tentativa.num_vista + 1,
                      copia: :undefined
                  }
              }

            true ->
              # hay nodos para sustituir a copiao
              (IO.ANSI.blue() <> "SUSTITUYO A COPIA") |> IO.puts()
              # cojo la tupla
              {nodoNuevo, latidosNuevo} = List.first(resto_nodos)
              # quito primer elemento de la lista porque será la copia
              nuevaLista = List.delete_at(resto_nodos, 0)

              %{
                estado_sist
                | tentativa: %{
                    estado_sist.tentativa
                    | num_vista: estado_sist.tentativa.num_vista + 1,
                      copia: nodoNuevo
                  },
                  copia_latido: @latidos_fallidos + 1,
                  resto_nodos: nuevaLista
              }
          end

        estadoNuevo
      end
  end
end
