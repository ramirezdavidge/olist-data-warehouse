# Proyecto Final – SQL for Data Engineer
## Pipeline de datos con Arquitectura Medallón (Bronce → Plata → Oro) sobre E-commerce Olist

Pipeline de datos 100 % en **SQL (T-SQL / SQL Server)** que toma los CSV del dataset público
[*Brazilian E-Commerce Public Dataset by Olist*](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)
(≈100 mil pedidos, 2016-2018) y los transforma en un **modelo estrella** listo para conectar a un dashboard.

```
   CSV (9 archivos)          BRONCE                 PLATA                    ORO
 ┌────────────────┐      ┌──────────────┐      ┌────────────────┐      ┌─────────────────────┐
 │ olist_*.csv    │ ───► │ copia cruda  │ ───► │ sin duplicados │ ───► │ modelo estrella     │ ───► Dashboard
 │ (fuente)       │ BULK │ + fecha_carga│ SQL  │ nulos tratados │ SQL  │ hechos + dimensiones│
 └────────────────┘      └──────────────┘      │ tipos correctos│      │ reglas de negocio   │
                                               └────────────────┘      └─────────────────────┘
```

---

## 1. Capas

| Capa | Esquema | Qué hace | Objetos |
|---|---|---|---|
| **Bronce** | `bronze` | Extrae de los CSV y guarda **sin modificar** (todo texto). Agrega `fecha_carga` (fecha y hora) y `archivo_origen`. | 9 tablas + `usp_load_bronze` |
| **Plata** | `silver` | Lee de Bronce. Elimina duplicados, gestiona nulos, estandariza tipos (fechas → `DATE`/`DATETIME2`, montos → `FLOAT`, cantidades → `INT`) y normaliza texto. | 9 tablas + `usp_load_silver` |
| **Oro** | `gold` | Lee de Plata. **Modelo estrella** con reglas de negocio y métricas. | 5 dimensiones, 3 hechos, 6 vistas + `usp_load_gold` |

## 2. Diagrama del modelo de datos final

![Modelo estrella](docs/modelo_estrella.png)

Fuente editable: [`docs/modelo_estrella.dot`](docs/modelo_estrella.dot) · versión Mermaid: [`docs/modelo_estrella.md`](docs/modelo_estrella.md)

| Tabla | Granularidad | Filas |
|---|---|---|
| `fact_ventas` | 1 fila por ítem de pedido | 112,650 |
| `fact_pagos` | 1 fila por pago | 103,886 |
| `fact_resenas` | 1 reseña por pedido | 98,673 |
| `dim_fecha` | 1 fila por día (2016-2018) | 1,096 |
| `dim_cliente` | 1 fila por cliente único | 96,096 |
| `dim_producto` | 1 fila por producto | 32,951 |
| `dim_vendedor` | 1 fila por vendedor | 3,095 |
| `dim_tipo_pago` | 1 fila por medio de pago | 5 |

**Decisiones de diseño**
- **Dos hechos de distinta granularidad** (ventas y pagos): unir pagos al ítem duplicaría los ingresos porque un pedido puede tener varios pagos.
- **`dim_cliente` por `customer_unique_id`**: en Olist el `customer_id` cambia en cada pedido; usar el ID único permite medir clientes recurrentes (2,997 clientes compraron más de una vez).
- **`dim_fecha` como dimensión *role-playing*** en `fact_ventas`: fecha de compra, estimada y real de entrega.
- Llaves sustitutas enteras (`*_key`) en todas las dimensiones.

## 3. Reglas de calidad y de negocio

### Plata (hallazgos reales del dataset y qué se hizo)
| Hallazgo en Bronce | Tratamiento en Plata |
|---|---|
| `geolocation`: 261,831 filas duplicadas exactas (26 %) y 42 puntos fuera de Brasil | `GROUP BY` para deduplicar + filtro de coordenadas |
| `order_reviews`: 814 `review_id` repetidos y 551 pedidos con más de una reseña | llave `(review_id, order_id)`; gana la respuesta más reciente |
| `order_reviews`: 87,656 títulos y 58,247 mensajes nulos | `'Sin título'` / `'Sin comentario'` + columna `tiene_comentario` |
| `products`: 610 sin categoría, sin nombre/descripción/fotos | `'sin_categoria'` y `0`; peso/dimensiones nulos (2 filas) se dejan en `NULL` |
| `product_category_translation`: faltan 2 categorías usadas en `products` | se agregan `pc_gamer` y `portateis_cozinha_e_preparadores_de_alimentos` (+ `sin_categoria`) |
| `orders`: 160 sin aprobación, 1,783 sin transportista, 2,965 sin entrega | **se dejan en `NULL`**: son nulos legítimos (cancelados, en tránsito) |
| Columnas mal escritas (`product_name_lenght`) | se corrigen a `product_name_length` |
| CP con ceros a la izquierda, ciudades con acentos/mayúsculas | `CHAR(5)` con relleno; ciudades en minúscula sin acentos |

### Oro (métricas y reglas)
| Métrica / regla | Definición |
|---|---|
| `es_venta_valida` | 0 si el pedido está `canceled` o `unavailable`; los ingresos siempre filtran = 1 |
| `total_item` | `precio + flete` |
| `dias_entrega_real` | días entre compra y entrega al cliente |
| `dias_retraso` | días de atraso vs. la fecha estimada (0 si llegó a tiempo, NULL si no se entregó) |
| `entregado_a_tiempo` | 1 si entrega ≤ fecha estimada |
| `tipo_cliente` | `Recurrente` si tiene 2+ pedidos, si no `Nuevo` |
| `region` | región de Brasil derivada del estado (Norte, Nordeste, Centro-Oeste, Sudeste, Sur) |
| `rango_peso` | Ligero (<500 g), Medio (500 g–2 kg), Pesado (>2 kg) |

**Vistas para el dashboard:** `vw_ventas_mensuales`, `vw_top_categorias`, `vw_top_vendedores`,
`vw_entregas_por_estado`, `vw_metodos_pago`, `vw_satisfaccion_mensual`.

## 4. Estructura del repositorio

```
olist-medallion-sql/
├── README.md
├── .gitignore
├── data/raw/                       ← aquí van los 9 CSV (no se suben a GitHub)
├── docs/
│   ├── modelo_estrella.png / .svg / .dot
│   └── modelo_estrella.md          (diagrama Mermaid)
└── sql/
    ├── 00_init_database.sql        crea la BD OlistDW y los esquemas
    ├── bronze/
    │   ├── 01_ddl_bronze.sql       tablas crudas + fecha_carga
    │   └── 02_proc_load_bronze.sql extracción CSV → Bronce (BULK INSERT)
    ├── silver/
    │   ├── 03_ddl_silver.sql       tablas tipadas y con llaves
    │   └── 04_proc_load_silver.sql limpieza Bronce → Plata
    ├── gold/
    │   ├── 05_ddl_gold.sql         modelo estrella (dimensiones y hechos)
    │   ├── 06_proc_load_gold.sql   transformación Plata → Oro
    │   └── 07_views_bi.sql         vistas de KPIs para el dashboard
    ├── run_pipeline.sql            ejecuta Bronce → Plata → Oro
    └── 99_validaciones.sql         conteos, duplicados, nulos y conciliación de montos
```

## 5. Cómo ejecutarlo (Visual Studio Code)

**Requisitos:** SQL Server 2017 o superior (Express/Developer o Docker) y la extensión
**SQL Server (mssql)** de Microsoft en VS Code.

1. Descarga el dataset de Kaggle y copia los 9 `.csv` en `data/raw/`.
2. En VS Code: pestaña *SQL Server* → *Add Connection* (servidor `localhost`, autenticación Windows o `sa`).
3. Abre y ejecuta (`Ctrl+Shift+E`) **en este orden**:
   `00_init_database.sql` → `01` → `02` → `03` → `04` → `05` → `06` → `07`.
4. Abre `sql/run_pipeline.sql`, cambia `@ruta_base` por la carpeta de los CSV y ejecútalo.
5. Ejecuta `sql/99_validaciones.sql` y compara con los valores esperados.

> **Importante:** `BULK INSERT` lee el archivo desde la máquina donde corre **SQL Server**.
> Si usas Docker, monta la carpeta dentro del contenedor, por ejemplo
> `-v "$(pwd)/data/raw:/var/opt/mssql/raw"` y usa `@ruta_base = N'/var/opt/mssql/raw/'`.
> En Windows, el servicio de SQL Server debe tener permiso de lectura sobre esa carpeta.

## 6. Resultados esperados (validación)

| Control | Esperado |
|---|---|
| Filas Bronce = filas de los CSV | customers 99,441 · geolocation 1,000,163 · order_items 112,650 · payments 103,886 · reviews 99,224 · orders 99,441 · products 32,951 · sellers 3,095 |
| `silver.geolocation` | 720,463 |
| Suma de `price` (Bronce = Plata = `fact_ventas`) | 13,591,643.70 |
| Suma de pagos (Bronce = Plata = `fact_pagos`) | 16,008,872.12 |
| Ingresos válidos (sin cancelados/no disponibles) | 13,494,400.74 en 98,199 pedidos |
| Entregas a tiempo (pedidos entregados) | ≈ 93 % |

## 7. Subir a GitHub

```bash
git init
git add .
git commit -m "Proyecto final: pipeline medallón Olist (SQL Server)"
git branch -M main
git remote add origin https://github.com/<tu-usuario>/olist-medallion-sql.git
git push -u origin main
```

Los CSV están en `.gitignore` (≈120 MB): en el repositorio solo va el código; quien lo clone descarga el dataset desde Kaggle.

## 8. Posibles mejoras
- Carga incremental (hoy es *full refresh* en cada corrida).
- `DECIMAL(12,2)` para montos en producción (aquí `FLOAT` por lineamiento del proyecto).
- Orquestación con SQL Server Agent / Airflow y registro de ejecuciones en una tabla de *logs*.
