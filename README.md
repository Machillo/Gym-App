# Sistema

App personal de entrenamiento gamificada para iPhone (iOS 17+). La app no te da rutinas: vos le pasás las tuyas y ella les da seguimiento. Lo único que impone son los ejercicios de la misión de castigo cuando no cumplís. Subís de nivel y de rango según lo que entrenás (pesas, circuitos, cardio, clases de box y Muay Thai), con penalizaciones duras si no cumplís. Todo vive en el teléfono: sin cuentas, sin servidor.

- Swift 5.9 · SwiftUI · SwiftData · Swift Charts · sin dependencias de terceros.
- Proyecto generado con [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`project.yml`); el `.xcodeproj` no se versiona.
- Zona horaria del motor: `America/Costa_Rica`. Semanas de lunes a domingo.

## Estructura

```
project.yml
Sistema/
  App/        punto de entrada e inyección de dependencias
  Models/     entidades SwiftData
  Engine/     lógica pura: curva, rangos, cumplimiento, XP, penalizaciones, pruebas, programas
  Services/   juego (orquestación), notificaciones locales, respaldo JSON, reloj inyectable
  Views/      pantallas y componentes
  Resources/  íconos y colores
SistemaTests/    motor, penalizaciones, catálogo, respaldo, calibración
SistemaUITests/  smoke test
scripts/calibrate.py   simulador rápido de la progresión (espejo del motor)
```

## Compilar y probar (Mac con Xcode 16 recomendado; 15 como mínimo)

```bash
brew install xcodegen
xcodegen generate
xcodebuild -scheme Sistema -destination 'platform=iOS Simulator,name=iPhone 15' build
xcodebuild -scheme Sistema -destination 'platform=iOS Simulator,name=iPhone 15' test
```

Si no tenés ese simulador, listá los disponibles con `xcrun simctl list devices available` y cambiá el `name=`.

## Instalar en tu iPhone

1. `xcodegen generate` y abrí `Sistema.xcodeproj`.
2. Xcode > Settings > Accounts: agregá tu Apple ID.
3. Seleccioná el target **Sistema** > *Signing & Capabilities*:
   - **Team**: tu equipo del Apple Developer Program (`UZ9P89YR3C`). Con la cuenta gratuita (*Personal Team*) también funciona, pero vence a los 7 días.
   - **Bundle Identifier**: debe ser único. Por defecto es `com.kennethalvarado.sistema`; si Xcode dice que no está disponible, cambialo (por ejemplo `com.tunombre.sistema.2026`). Para no repetirlo cada vez que regenerás el proyecto, editá `PRODUCT_BUNDLE_IDENTIFIER` y `DEVELOPMENT_TEAM` en `project.yml`.
4. Conectá el iPhone por cable, desbloquealo y aceptá "Confiar en esta computadora".
5. En el iPhone activá el **Modo de desarrollador** (Ajustes > Privacidad y seguridad > Modo de desarrollador) y reiniciá.
6. Elegí tu iPhone como destino y presioná **Run** (⌘R).
7. La primera vez iOS bloquea la app: andá a **Ajustes > General > VPN y gestión de dispositivos**, tocá tu Apple ID y **Confiar**.

La única capacidad de cuenta paga es **HealthKit** (Apple Salud); no hay iCloud, push remotas, App Groups ni widgets. Con la cuenta gratuita HealthKit no firma.

## Reinstalar sin perder datos

Con el Apple Developer Program el perfil de desarrollo dura 1 año (el actual vence el 6 nov 2027) y además se renueva cada vez que reinstalás desde Xcode. Con el Personal Team vence a los 7 días. Cuando vence, la app deja de abrir. Para renovarla:

1. Conectá el iPhone y presioná **Run** otra vez en Xcode (mismo bundle ID y mismo team).
2. **No desinstales la app**: instalar encima conserva la base de datos de SwiftData.
3. Por seguridad, exportá un respaldo de vez en cuando: Ajustes > Respaldo > *Exportar respaldo JSON* (guardalo en Archivos). Si alguna vez tenés que desinstalar o cambiar el bundle ID, lo recuperás con *Importar respaldo JSON*.

Si cambiás el bundle ID, iOS lo trata como otra app (datos vacíos): importá el respaldo.

## Programas del gimnasio

Un programa agrupa los días de tu rutina y su fecha de cambio. Está en Entrenar > Rutinas > **+** > *Programa completo (pegar texto)*: escribís o pegás todo de una vez y revisás la vista previa antes de guardar. Para copiar desde una captura, en Fotos mantené presionado el texto y tocá Copiar.

```
Día 1 - Bi Series
Full Body
BI SERIES X 3 ROUNDS
Trap bar deadlift 6 reps
Bent over row DB
10 reps

Día 2 - AMRAP
AMRAP 15 MIN ON
Gorilla Row KB 12 reps c/l
DB Thrusters 12 reps 1 min
```

El ejercicio y su medida pueden ir en una o dos líneas. Después de la medida van la nota (`c/l`) y, al final, el descanso (`1 min`). En una bi-serie, cada par de ejercicios es un bloque.

*Usar en un itinerario* precarga el plan semanal, con la fecha de cambio como fin. El itinerario sigue las reglas de siempre: al vencer tenés 48 h de gracia para cargar el siguiente.

### Peso en kg o lb

Cada campo de peso tiene su botón kg/lb. Internamente todo se guarda en kg, así las marcas y el e1RM comparan el peso real sin importar la unidad en que lo escribiste. Cambiar el botón convierte lo que se ve (25 kg → 55.12 lb), no el peso.

## Cómo funciona

### Cumplimiento
- **Fuerza**: reps hechas / (series × reps prescritas).
- **Circuito, bi-serie y tabata**: (rondas hechas / rondas prescritas) × promedio por ejercicio de reps o tiempo real / prescrito.
- **AMRAP**: tiempo real / tiempo prescrito. Las rondas completadas se guardan como resultado, no como meta.
- **Cardio**: distancia real / prescrita (o tiempo si no hay distancia).
- **Clase**: duración real / prescrita.
- Cada bloque topa en 100 % (lo real se guarda igual para el historial). La sesión es el promedio ponderado por los minutos estimados de cada bloque.
- Más peso que lo prescrito con las mismas reps queda marcado como **mejora** en el historial del ejercicio.

### XP
`XP = base del tipo × factor de duración × factor de intensidad × cumplimiento`, +10 % antes de las 6 a. m. Topes: 200 XP por día y 700 XP por semana.

### Penalizaciones
Se evalúan al abrir la app y al volver a primer plano, día cerrado por día cerrado (idempotente). El día del onboarding y el día en curso nunca se castigan.

| Situación | Efecto |
|---|---|
| Día planeado sin sesión | −100 XP, falta completa, Zona de penalización + misión de castigo (25 min) |
| Sesión planeada con < 50 % | −50 % del XP de esa sesión, media falta |
| Misión de castigo sin cumplir en 48 h | otra falta completa |
| 3 faltas (sumando medias) en una semana | −1 nivel (otro cada 3 faltas más) |
| Itinerario vencido + 48 h de gracia | falta por cada día que habría sido de entrenamiento |
| Modo lesión/enfermo | congela penalizaciones y racha (máx. 14 días por activación) |

Si el XP cae por debajo del piso del rango, perdés el rango y tenés que volver a pasar la prueba (sin repetir el tiempo mínimo). Piso absoluto: Rango E, nivel 1. Las sesiones libres dan XP pero no borran faltas.

### Temporizador

AMRAP, For Time (con o sin límite), EMOM, Tabata, Mix (varios temporizadores seguidos) y Descanso. Cada uno admite preparación y series con descanso entre ellas; For Time y AMRAP, señal por intervalo; EMOM, modo Death By. Recuerda la última configuración de cada modo y muestra el tiempo total.

Se abre desde Entrenar o desde el registro de una sesión, ya configurado con el bloque; al abrirlo desde un AMRAP, las rondas y el tiempo pasan a la sesión. Cuenta por hora real y mantiene la pantalla encendida. El sonido se oye aunque el iPhone esté en silencio y se mezcla con tu música; si el teléfono se bloquea deja de sonar, pero una notificación avisa al terminar.

### Último peso

Al registrar, cada ejercicio muestra el peso más alto de la última vez que lo hiciste y **Usar** lo copia con su unidad.

### Corregir sesiones

En Entrenar > Historial de sesiones, tocar una sesión la edita y deslizarla la borra. El XP y los atributos se recalculan con las mismas reglas y topes. No cambia lo que un día ya cerrado dejó (faltas, racha o pruebas superadas). Las sesiones de castigo no se pueden corregir.

### Clases

Box, Muay Thai y MMA se registran con **Registrar clase**. Las tres cuentan para las pruebas de ascenso.

### Cuerpo

En Progreso > Cuerpo se apunta peso (kg o lb), grasa y 11 medidas en cm, con gráfico y cambio desde el primer registro. No da XP.

Arriba hay una figura de frente: tocá una zona (cuello, hombros, pecho, cintura, cadera, brazos, antebrazo, muslos, pantorrilla) y anotá la medida nueva; se guarda en el registro de hoy (si no hay, se crea). Peso y grasa se anotan igual desde sus tarjetas. Las zonas pintadas ya tienen medida. La figura es de frente: tu lado derecho queda a la izquierda de la pantalla.

### Peso en Entrenar

Arriba de Entrenar está el peso corporal: el último, hace cuánto, el cambio contra el anterior y la tendencia de los últimos 10. *Actualizar peso* lo anota al toque. Al registrar una sesión (no al corregirla) hay un campo opcional *Peso al terminar*; si lo llenás, queda como tu peso de hoy.

### Medición InBody

En Cuerpo, *Nueva medición* abre un paso a paso: peso, masa muscular, % de grasa, grasa visceral y puntos InBody. Cada dato se elige arrastrando una regla (vibra en cada rayita), con − / + o tocando el número para escribirlo; arranca en tu última medición y muestra el cambio contra ella (verde si va bien, rojo si no). Al final hay un resumen con la fecha y la grasa en kg y la masa magra calculadas. Si ese día ya tenías medidas de la figura, se guarda en el mismo registro.

### Apple Salud

Se conecta desde Estado o Ajustes > Apple Salud y se sincroniza al abrir la app.

- **Del Watch al Sistema**: los entrenamientos de los últimos 7 días (desde que creaste el jugador) entran solos. Si ese día ya registraste una sesión del mismo tipo (fuerza/HIIT, cardio o pelea), se une a ella con calorías y pulso; si no, se agrega como sesión con su XP. Si después registrás esa sesión, se une a la del Watch y se cobra solo la diferencia de XP: nunca se duplica. Una sesión del Watch borrada no vuelve.
- **Del Sistema a Salud**: solo las clases de box, muay thai y MMA (lo demás lo graba el Watch), con calorías estimadas: (MET − 1) × peso × horas, ajustado por RPE (MET: box 7,8; muay thai y MMA 9). También peso, grasa, masa magra y cintura. Corregir o borrar en el Sistema corrige o borra en Salud.
- **Balanza**: peso y grasa de otra app entran al registro de ese día si no tenía ese dato, y no se devuelven a Salud.
- **Estado** muestra los aros de hoy y los pasos con el promedio de 7 días. Ni calorías ni pasos dan XP.

### Diseño

Fondo casi negro, tarjetas planas sin brillo y un solo acento verde lima para lo que importa (acciones, progreso, rango). Las alertas llevan una franja de color a la izquierda. Los colores y estilos de botón viven en `Sistema/Views/Components/Theme.swift`.

### Perfil

Se calcula solo: el nivel sale del rango (Novato, Aprendiz, Competidor, Veterano, Élite, Maestro, Leyenda) y el estilo, de los minutos de las últimas 8 semanas entre pelea, fuerza y acondicionamiento. Cada cambio queda en **Tu evolución**.

### Retos

Semanales y mensuales, con metas que se ajustan a tu periodo anterior, más logros permanentes. No dan XP, para no alterar la curva de progresión.

### Respaldo y vencimiento

Cada 7 días se guarda una copia en Archivos > En mi iPhone > Sistema > Respaldos (quedan las últimas 4). Desinstalar la app también las borra. La app lee cuándo vence su perfil de instalación y avisa 48, 24 y 3 horas antes.

### Días pendientes

Los días planeados de los últimos 7 días que no tienen sesión aparecen en Estado y se pueden registrar tarde: suman XP, atributos e historial. No borran una falta ya cobrada ni suman racha, porque ese día ya se evaluó.

### Cambiar de programa

En un build de desarrollo, lanzar con `-adoptProgram <nombre>` pone ese programa en lugar del itinerario activo, desde su misma fecha de inicio y hasta la fecha de cambio del programa, y borra las rutinas del itinerario reemplazado. Lanzarlo de nuevo no cambia nada.

### Historial previo

El entrenamiento anterior a la app se reconoce una sola vez, como XP, sin botón en la app: en un build de desarrollo se lanza con `-priorHistoryXP <xp>`. Da por superadas las pruebas de los rangos alcanzados, pero el tiempo mínimo y los requisitos de la siguiente prueba cuentan desde ese día. No es una sesión: no toca racha ni atributos.

### Pruebas de ascenso
Al llegar al último nivel de un rango quedás topado; el XP extra se guarda como desborde (máximo 1 nivel). La prueba se habilita tras el tiempo mínimo en el rango y se supera sola cuando registrás la sesión que completa el último requisito:

| Rango destino | Tiempo mínimo en el rango anterior | Requisitos |
|---|---|---|
| D | 1 mes | 3 semanas seguidas ≥ 70 % |
| C | 3 meses | 6 semanas ≥ 75 % · mejorar 5 % una marca |
| B | 6 meses | 8 semanas ≥ 80 % · mejorar 10 % · 8 clases |
| A | 12 meses | 12 semanas ≥ 85 % · mejorar 15 % · 20 clases |
| S | 24 meses | 16 semanas ≥ 85 % · mejorar 20 % · 40 clases |
| SS | 36 meses | 24 semanas ≥ 90 % · mejorar 25 % · 60 clases |

"Marca" = e1RM (Epley) de un ejercicio o ritmo de cardio (min/km), comparado con tu mejor marca antes del rango (o la primera dentro del rango).

## Constantes finales de progresión

Todas viven en `Sistema/Engine/Progression.swift` y se replican en `scripts/calibrate.py`.

| Constante | Valor |
|---|---|
| XP para pasar de L a L+1 | `round(50 + 7.3 × L^1.5)` (coeficiente ajustado de 7.0 a 7.3) |
| Niveles | 100 (XP total para el 100: 293 308) |
| Base por tipo de sesión | 100 XP (fuerza, circuito, cardio, clase) |
| Factor de duración | minutos / 60, entre 0.25 y 1.5 |
| Factor de intensidad | 1 + 0.05 × (RPE − 7), entre 0.85 y 1.15 |
| Bonus madrugada | +10 % antes de las 6:00 |
| Topes | 200 XP/día · 700 XP/semana |
| Falta completa | −100 XP |
| Media falta | −50 % del XP de la sesión (cumplimiento < 50 %) |
| Bajada de nivel | cada 3 faltas en una semana calendario |
| Ventana de misión de castigo | 48 h, mínimo 20 min |
| Gracia por itinerario vencido | 2 días |
| Modo lesión | máx. 14 días por activación |

Rangos: E 1–9 · D 10–24 · C 25–44 · B 45–64 · A 65–84 · S 85–99 · SS 100. Cada rango se divide en III → II → I (el sobrante de niveles va a las divisiones altas, p. ej. C: III 25–30, II 31–37, I 38–44).

### Calibración (5 sesiones de 60 min por semana, RPE 7)

Resultado de `python scripts/calibrate.py` (lo mismo verifica `CalibrationTests`):

| Perfil | D | C | B | A | S | SS |
|---|---|---|---|---|---|---|
| 100 % | 1.0 meses | 4.9 meses | 1.59 años | 3.89 años | 7.54 años | 11.27 años |
| 100 % entrenando a las 4:30 | 1.0 meses | 4.6 meses | 1.46 años | 3.55 años | 6.86 años | 10.26 años |
| 80 % | 1.0 meses | 5.8 meses | 1.97 años | 4.84 años | 9.40 años | 14.07 años |
| 60 % | 1.0 meses | 7.5 meses | 2.60 años | 6.43 años | 12.51 años | 18.73 años |

Con el coeficiente original (7.0) el perfil perfecto ya caía en la tabla, pero entrenando antes de las 6 a. m. llegaba a SS en 9.8 años; por eso se subió a 7.3. La calibración asume que los requisitos de cada prueba se cumplen apenas se habilita.

## Datos de ejemplo

Solo en builds Debug: Ajustes > Depuración > activá *Herramientas de datos de ejemplo* (apagado por defecto) y tocá *Cargar datos de ejemplo*.
