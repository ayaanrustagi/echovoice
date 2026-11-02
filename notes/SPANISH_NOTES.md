# Spanish localization notes

EchoVoice supports English and Latin American Spanish (`es`). The brand name remains EchoVoice. `Localizable.xcstrings` contains UI, accessibility, vocabulary, reply, error, and report strings. `InfoPlist.xcstrings` contains the four permission explanations. `AppShortcuts.xcstrings` contains Siri shortcut phrases. The synchronized Xcode group includes all three catalogs automatically; the project declares `es` as a known region.

## Language and saved content

- `AppLanguage` uses the bundle's resolved language, including the iOS per-app language and the Xcode scheme override. English remains the development language and fallback.
- New boards start with the matching English or Spanish quick phrases. Vocabulary categories, core words, conversation repairs, situation phrases, personal-information prefixes, journal reading, and deterministic Listen replies follow the app language.
- Existing saved phrases, recordings, personal details, drafts, shortcuts, and history remain the person's own content. They are never machine-translated or overwritten. After changing an existing installation's language, use Settings → Board Language → add starter phrases to add Spanish quick phrases. Existing recordings continue to play their original audio.
- The existing Board Language preference remains an explicit choice for HELP and adding starter phrases; without a saved choice it follows the app language. It does not change the UI language. This preserves bilingual boards and existing English preferences.
- Speech detects English or Spanish per utterance, biased toward the board language for ambiguous short words. Spanish prefers `es-MX`, then `es-US`, then any available `es` voice. A Personal Voice is used only for text matching its language; English Personal Voice behavior is preserved. Recordings take precedence over synthesis.
- Listen and journal recognition try the user's region in the app language, then regional variants supporting on-device recognition. Both require on-device recognition and never fall back to a server. Listen explains when unavailable; the journal still records and displays why words-understood scoring was skipped or failed.
- Sentence expansion and smart replies explicitly request Spanish output in Spanish mode. The sentence guard checks selected sensitive words exactly (including `no`, `sí`, `si`, `ni`, `nunca`, and `ayuda`), retains selected content, and permits Spanish grammatical scaffolding. Smart replies block Spanish emergency language and inflections. Nothing speaks without the person's selection.
- The hands-free spelling board includes Ñ and accented Spanish vowels in Spanish mode. Persistent identifiers, enum raw values, settings keys, file formats, and user-authored content remain stable.

## Test in Xcode

1. Open `EchoVoice.xcodeproj`, select scheme **EchoVoice**, and choose **Product → Scheme → Edit Scheme → Run → Options**.
2. Set **App Language** to **Spanish** and **App Region** to **Mexico**. Test on a fresh installation first; onboarding and the initial quick board should be Spanish. Also verify Spanish with a US region and the device/per-app language setting without a scheme override.
3. Visit every tab, onboarding, caregiver settings, phrase editor, recording studio, tags, hands-free setup/tutorial, conversation workspace, partner display, and suggestion explanations. Use the largest text size and VoiceOver; check button fit and accessibility announcements. Export a journal CSV/PDF and check Spanish headings and layout. Check Siri shortcut titles/phrases too.
4. Speak quick phrases, vocabulary, HELP, repairs, personal introductions, and free text. Check “Sí”, “No”, “Tengo sed”, “Necesito ayuda”, and “Te quiero”, including repeated HELP and Stop. Verify an English recording on a bilingual board still plays unchanged.
5. On a physical device with Spanish recognition available, test Listen with “¿Quieres agua?”, “¿Quieres té o café?” and “¿Cómo estás?”. Test journal recognition using the Spanish reference sentence. On a device without Spanish on-device support, and with recognition permission denied, verify the clear message and usable recording flow. No audio should leave the device.
6. On an Apple Intelligence device, expand “agua fría” and “no agua”. Confirm Spanish output, retained content/negation, no added affirmation, negation, emergency, or topic, and no automatic speech. Test Spanish smart replies and unsupported-model behavior.
7. Switch the scheme to **English**. Verify the original English UI and starter text, on-device recognition, sentence expansion, and an authorized English Personal Voice. Test a saved/recorded board across language changes; recordings and user-authored wording must survive. Journal readings use different reference sentences across languages: compare trends within one language rather than interpreting a language switch as voice change.

Build from `EchoVoice-iOS/`:

```sh
xcodebuild -project EchoVoice.xcodeproj -scheme EchoVoice -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DD CODE_SIGNING_ALLOWED=NO build
./Scripts/run_tests.sh
./Scripts/run_localization_tests.sh
python3 Scripts/check_localizations.py build/DD/Build/Intermediates.noindex/EchoVoice.build/Debug-iphonesimulator/EchoVoice.build/Objects-normal/arm64
```

`run_localization_tests.sh` compiles the real catalog into a temporary macOS bundle and runs it once in English and once in Mexican Spanish; it needs no simulator. The existing logic suites include Spanish reply classification and sentence/model guardrail regressions. The catalog check verifies Spanish coverage, format arguments, and (when given the build directory) compiler-extracted string coverage.

## Human review

A native Mexican/Latin American Spanish speaker should review every row below, especially the spoken vocabulary, medical requests, HELP, and conversational repairs. Check warmth, brevity, tú forms, regional vocabulary (“cobija”, “tele”, “carro”, “camión”), role/gender choices, and how isolated core words combine into sentences. The Spanish journal sentence is a translation of the existing reading, not a validated Spanish clinical assessment. Also listen to generated model options on a supported device: those options are created at runtime and cannot be exhaustively listed here.

The tables exhaustively list catalog translations and the explicit Spanish starter/HELP content. `%@`, `%d`, `%lld`, and numeric format patterns are placeholders; `%%` displays a percent sign. `${applicationName}` and `${phrase}` are system substitutions. Review complete rendered messages with real values as well as the templates. Identical punctuation/number-only/brand entries are retained for catalog coverage.

### Explicit quick phrases and HELP

| Spoken Spanish | Button label / purpose |
| --- | --- |
| Sí | Sí |
| No | No |
| Quisiera un poco de agua, por favor | Agua |
| Necesito ir al baño | Baño |
| Tengo dolor, ayúdame por favor | Dolor |
| Tengo hambre | Hambre |
| Tengo frío | Frío |
| ¿Me das una cobija? | Cobija |
| ¿Me ayudas a sentarme? | Sentarme |
| Te quiero | Te Quiero |
| ¿Puedes prender la tele? | Tele |
| ¿Puedes poner música? | Música |
| Necesito ayuda. Por favor, ven. | HELP: repeated aloud until stopped |

### Localizable.xcstrings

| English / source | Spanish |
| --- | --- |
|  (cursor) |  (cursor) |
|  and  |  y  |
|  or  |  o  |
|  · calibrated |  · calibrado |
|  — not usable |  — no útil |
|  — usable |  — útil |
| ! | ! |
| "%@" | "%@" |
| %.0f dB above room | %.0f dB sobre el ruido del lugar |
| %.0f wpm | %.0f palabras/min |
| %.1f WPM | %.1f palabras/min |
| %.1f seconds | %.1f segundos |
| %.2f%% clipped | %.2f%% con distorsión |
| %@ | %@ |
| %@ %@ right after “%@” | %@ %@ justo después de «%@» |
| %@ check-ins in your personal history | %@ lecturas en tu historial personal |
| %@ custom phrases recorded. | %@ frases personalizadas grabadas. |
| %@ of %@ check-ins to start your personal baseline | %@ de %@ lecturas para empezar tu referencia personal |
| %@ of %@ recordings for your baseline | %@ de %@ grabaciones para tu referencia |
| %@ of %@ saved in your voice | %@ de %@ guardadas con tu voz |
| %@ of %@ words, checked on this device | %@ de %@ palabras, revisadas en este dispositivo |
| %@ of 5 | %@ de 5 |
| %@ of those in the %@ | %@ de esas selecciones en %@ |
| %@ percent of words understood. Heard: %@ | Se entendió el %@ por ciento de las palabras. Se escuchó: %@ |
| %@ phrases still in a synthetic voice | %@ frases aún usan una voz sintética |
| %@ readings, from %@ to %@ words per minute | %@ lecturas, de %@ a %@ palabras por minuto |
| %@ recordings saved | %@ grabaciones guardadas |
| %@ room (%.0f dBFS) · speaking at %d%% | Lugar %@ (%.0f dBFS) · voz al %d%% |
| %@ · %.0f Hz · %.0f cm · %@ · blink L %.2f R %.2f | %@ · %.0f Hz · %.0f cm · %@ · parpadeo I %.2f D %.2f |
| %@ · %@s dwell%@ | %@ · %@s de mirada%@ |
| %@, in your recorded voice | %@, con tu voz grabada |
| %@: %@ | %@: %@ |
| %@: %@, S/N %.1f%@ | %@: %@, S/R %.1f%@ |
| %@: no data | %@: sin datos |
| %d of %d · %.1fs · %d wrong | %d de %d · %.1fs · %d errores |
| %lld | %lld |
| %lld / %lld | %lld / %lld |
| %lld%% | %lld%% |
| + %@ more below | + %@ más abajo |
| , recorded in your own voice | , grabada con tu propia voz |
| 123 Main Street, Austin, Texas | 123 Main Street, Austin, Texas |
| 5 | 5 |
| A little fast | Un poco rápido |
| A little slow | Un poco lento |
| A reading is flagged once it sits more than %@ standard deviations from your own baseline, built from your %@ earlier readings. You are never compared with anyone else. Pausing uses its own rule instead, because a pause ratio near zero makes standard deviations misleading. | Se marca un cambio si una lectura se aleja más de %@ desviaciones estándar de tu referencia, calculada con tus %@ lecturas anteriores. Nunca se te compara con otras personas. Las pausas usan otra regla: cerca de cero, las desviaciones estándar pueden confundir. |
| A short code to find this phrase fast. | Un código corto para encontrar esta frase rápido. |
| About one minute. Nothing leaves this phone. | Toma cerca de un minuto. Nada sale de este teléfono. |
| About you | Sobre ti |
| Actions | Acciones |
| Active | Activa |
| Add | Agregar |
| Add %@ English starter phrases | Agregar %@ frases iniciales en inglés |
| Add %@ to draft | Agregar %@ al borrador |
| Add %@ to sentence | Agregar %@ a la oración |
| Add a new phrase | Agregar una frase |
| Add a phrase on the Speak tab, then record it here in your own voice. | Agrega una frase en Hablar y grábala aquí con tu propia voz. |
| Add at least one phrase before exporting. | Agrega al menos una frase antes de exportar. |
| Add contact, medical, and emergency details for fast one-tap introductions. | Agrega datos de contacto, médicos y de emergencia para presentarte con un toque. |
| Add sample readings | Agregar lecturas de ejemplo |
| Add shortcut for %@ | Agregar atajo para %@ |
| Add your first phrase | Agrega tu primera frase |
| Address | Dirección |
| Adds them to the end of the board. Your own phrases are not changed. | Se agregan al final del tablero. Tus propias frases no cambian. |
| After tapping Record, wait a beat before speaking. | Después de tocar Grabar, espera un momento antes de hablar. |
| All | Todas |
| All %@ phrases play back in your own recorded voice. | Las %@ frases se reproducen con tu voz grabada. |
| All Words | Todas las palabras |
| Allergies | Alergias |
| Allergies or none | Tus alergias o ninguna |
| Allow Camera for Face Tracking | Permitir cámara para seguir tu cara |
| Allow camera access on the previous step to set up hands-free control. | Permite el acceso a la cámara en el paso anterior para configurar el control sin manos. |
| Analyzed in %@ milliseconds on this device | Análisis en %@ milisegundos en este dispositivo |
| Analyzed in %@ ms on this device | Análisis en %@ ms en este dispositivo |
| Anything you enter becomes a one-tap phrase in Build > Personal. Leave a field blank to hide it from the board. | Lo que escribas se convierte en una frase de un toque en Construir > Personal. Deja un campo vacío para ocultarlo del tablero. |
| Apple Personal Voice | Voz personal de Apple |
| Apple Personal Voice lets you record your voice while you still can, and recreate it on-device. EchoVoice speaks your phrases in that voice — so it always sounds like you. Everything is generated on this device and never uploaded. | La voz personal de Apple te permite grabar tu voz mientras puedas y recrearla en el dispositivo. EchoVoice dice tus frases con esa voz para que suene como tú. Todo se genera en este dispositivo y nunca se sube a internet. |
| Apple Personal Voice requires iOS 17.0 or newer. | La voz personal de Apple requiere iOS 17.0 o posterior. |
| Appointment | Cita |
| Appointments | Citas |
| Articulation rate | Velocidad de articulación |
| Ask a question and replies will appear here. | Haz una pregunta y las respuestas aparecerán aquí. |
| Avery Johnson | Alex García |
| Añadir %@ frases en español | Agregar %@ frases en español |
| BUTTON LABEL | TEXTO DEL BOTÓN |
| Back | Atrás |
| Back to categories | Volver a categorías |
| Background noise | Ruido de fondo |
| Backspace | Borrar letra |
| Backup & Transfer | Respaldo y transferencia |
| Blink five times quickly, then close your eyes and hold for 2 seconds. Or rest on the red HELP button: it needs a longer look than other buttons, so it is not chosen by accident. | Parpadea cinco veces rápido y luego cierra los ojos por 2 segundos. También puedes mirar el botón rojo AYUDA: requiere una mirada más larga para evitar activarlo sin querer. |
| Board Density | Densidad del tablero |
| Board Language | Idioma del tablero |
| Board density | Densidad del tablero |
| Board language | Idioma del tablero |
| Board locked | Tablero bloqueado |
| Body & Health | Cuerpo y salud |
| Bring to your SLP / Clinician | Lleva a tu terapeuta o médico |
| Brings back what you just deleted | Recupera lo que acabas de borrar |
| Build | Construir |
| Build a sentence | Construir una oración |
| Building Baseline | Creando referencia |
| COLOR | COLOR |
| Call | Llamar |
| Call %@ | Llamar a %@ |
| Call For Help | Pedir ayuda |
| Calling for HELP | Pedir AYUDA |
| Calling for Help | Pidiendo ayuda |
| Calls your emergency contact | Llama a tu contacto de emergencia |
| Camera Access Granted | Acceso a cámara permitido |
| Camera unavailable | Cámara no disponible |
| Can't see your face. Move back into the camera's view. | No se ve tu cara. Vuelve a colocarte frente a la cámara. |
| Cancel | Cancelar |
| Check | Revisar |
| Check directions | Revisar direcciones |
| Check for my Personal Voice | Buscar mi voz personal |
| Check room | Medir ruido |
| Check the microphone isn't covered, then try again. | Revisa que el micrófono no esté tapado e intenta de nuevo. |
| Checking iOS Personal Voice status... | Revisando la voz personal de iOS... |
| Checking that the cursor follows you. | Revisando que el cursor te siga. |
| Checking the room needs microphone access. | Para medir el ruido se necesita acceso al micrófono. |
| Checking… | Revisando… |
| Choice: %@ | Opciones: %@ |
| Choose a Category | Elige una categoría |
| Choose a button | Elige un botón |
| Choose a category | Elegir categoría |
| Choose at least two words first. | Primero elige al menos dos palabras. |
| Chosen %@ %@ out of %@ | Elegida %@ %@ de %@ selecciones |
| Clear | Borrar |
| Clear message | Borrar mensaje |
| Clear recent messages | Borrar mensajes recientes |
| Clear recording | Grabación clara |
| Close | Cerrar |
| Close eyes to turn the page | Cerrar los ojos para cambiar de página |
| Closer to zero is more likely. The three terms are added, not multiplied, because they are logs — that is what keeps the numbers from underflowing. | Más cerca de cero significa más probable. Se suman los tres valores porque son logaritmos; así los números no se vuelven demasiado pequeños. |
| Color %@ | Color %@ |
| Come back. Done. | Regresa. Listo. |
| Comfort | Comodidad |
| Comfortable | Amplio |
| Communication Board | Tablero de comunicación |
| Compact | Compacto |
| Conditions you want others to know | Condiciones que quieres compartir |
| Connected | Conectada |
| Continue | Continuar |
| Control it with small head movements. | Controla la app con pequeños movimientos de cabeza. |
| Conversation | Conversación |
| Conversation Workspace | Espacio de conversación |
| Conversation draft | Borrador de conversación |
| Conversation workspace | Espacio de conversación |
| Core | Básicas |
| Couldn't Add Phrase | No se pudo agregar la frase |
| Couldn't build the export file. | No se pudo crear el archivo para exportar. |
| Couldn't connect to that tag. Try again. | No se pudo conectar con esa etiqueta. Intenta de nuevo. |
| Couldn't find those recordings on this device. | No se encontraron esas grabaciones en este dispositivo. |
| Couldn't load saved phrases. Please reopen EchoVoice to retry. | No se pudieron cargar tus frases. Cierra y abre EchoVoice para intentar de nuevo. |
| Couldn't open that file. | No se pudo abrir ese archivo. |
| Couldn't play recording. | No se pudo reproducir la grabación. |
| Couldn't play that recording. Please record it again. | No se pudo reproducir. Graba la frase de nuevo. |
| Couldn't prepare the audio files. Try again. | No se pudieron preparar los archivos de audio. Intenta de nuevo. |
| Couldn't prepare the tag data. | No se pudieron preparar los datos de la etiqueta. |
| Couldn't read that tag. | No se pudo leer esa etiqueta. |
| Couldn't save starter phrases. Please reopen EchoVoice to retry. | No se pudieron guardar las frases iniciales. Cierra y abre EchoVoice para intentar de nuevo. |
| Couldn't save that recording. Your previous recording is unchanged. | No se pudo guardar. Tu grabación anterior sigue igual. |
| Couldn't save to that tag: %@ | No se pudo guardar en la etiqueta: %@ |
| Couldn't save. Your draft is still here. | No se pudo guardar. Tu borrador sigue aquí. |
| Couldn't see you steadily. Try again. | No se pudo verte de forma estable. Intenta de nuevo. |
| Couldn't start recording. | No se pudo empezar a grabar. |
| Couldn't start recording. Check microphone access and try again. | No se pudo grabar. Revisa el acceso al micrófono e intenta de nuevo. |
| Couldn't use the microphone. Try again. | No se pudo usar el micrófono. Intenta de nuevo. |
| Couldn't write options for that. Your words are unchanged. | No se pudieron escribir opciones. Tus palabras siguen igual. |
| Create a Personal Voice | Crea una voz personal |
| Create shortcuts from Settings → Manage Phrase Cards. Exact wording stays under your control. | Crea atajos en Configuración → Administrar frases. Tú controlas las palabras exactas. |
| Current message | Mensaje actual |
| Cursor followed | El cursor siguió |
| Cursor uses: %@ · %@ | El cursor usa: %@ · %@ |
| Customize Preferences | Personaliza tus preferencias |
| DISCLAIMER: EchoVoice is a personal voice journal, NOT a medical device. This report displays on-device acoustic measurements (speaking rate, pause duration, pitch stability) captured during repeat readings of one fixed reference sentence. Bring this summary to your Speech-Language Pathologist (SLP) to review trends. | AVISO: EchoVoice es un diario personal de voz, NO un dispositivo médico. Este informe muestra medidas acústicas tomadas en el dispositivo (velocidad, pausas y estabilidad del tono) al leer la misma oración. Lleva este resumen a tu terapeuta del habla para revisar los cambios. |
| Dark green-black background with bright text and controls. | Fondo verde oscuro con texto y controles brillantes. |
| Date | Fecha |
| Date of birth | Fecha de nacimiento |
| Date,Speaking Rate (WPM),Pause Ratio (%),Pitch Stability,Articulation Rate (WPM excluding pauses),Status<br> | Fecha,Velocidad (palabras/min),Pausas (%),Estabilidad del tono,Velocidad de articulación (palabras/min sin pausas),Estado<br> |
| Delete %@ | Borrar %@ |
| Delete %@ profile | Borrar perfil %@ |
| Delete Recording | Borrar grabación |
| Delete recording | Borrar grabación |
| Delete this recording? | ¿Borrar esta grabación? |
| Deleted the recording of “%@” | Se borró la grabación de «%@» |
| Describe | Describir |
| Didn't get a reading. Try again. | No se obtuvo una lectura. Intenta de nuevo. |
| Directions | Direcciones |
| Distance from usual | Diferencia de lo habitual |
| Distorted (too loud) | Distorsión (muy fuerte) |
| Done | Listo |
| Down | Abajo |
| Draft | Borrador |
| Draft ready to continue | Borrador listo para continuar |
| Draft: %@ | Borrador: %@ |
| Dwell time | Tiempo de mirada |
| EchoVoice | EchoVoice |
| EchoVoice AAC App | App de CAA EchoVoice |
| EchoVoice Patient Voice Journal | Diario de voz de EchoVoice |
| EchoVoice Speech Journal Summary Report | Resumen del diario de voz de EchoVoice |
| EchoVoice Speech Journal — Summary Report | Diario de voz de EchoVoice — Resumen |
| EchoVoice Voice Keepsake | Recuerdo de voz EchoVoice |
| EchoVoice can see you clearly. | EchoVoice puede verte bien. |
| EchoVoice couldn't see enough head movement. Turn a little further toward each dot. | EchoVoice no detectó suficiente movimiento de cabeza. Gira un poco más hacia cada punto. |
| EchoVoice couldn't see your eyes move enough. Look right at each dot, all the way to the edge. | EchoVoice no detectó suficiente movimiento de ojos. Mira cada punto hasta la orilla. |
| EchoVoice is an AAC and personal voice-journal tool, not a medical device. It does not diagnose, screen, or monitor any condition. | EchoVoice es una herramienta de comunicación y diario personal de voz, no un dispositivo médico. No diagnostica, detecta ni vigila ninguna condición. |
| EchoVoice learns which phrases you reach for, when you reach for them, and what you tend to say next. | EchoVoice aprende qué frases eliges, cuándo las eliges y qué sueles decir después. |
| EchoVoice lost sight of your face. Keep your face in view of the front camera, in good light, and try again. | EchoVoice dejó de ver tu cara. Mantén la cara frente a la cámara, con buena luz, e intenta de nuevo. |
| EchoVoice measured and corrected this phone's direction during setup. | EchoVoice midió y corrigió la dirección de este teléfono al configurar. |
| EchoVoice needs permission to use your Personal Voice. | EchoVoice necesita permiso para usar tu voz personal. |
| EchoVoice will speak in your own voice. | EchoVoice hablará con tu propia voz. |
| Edit Personal Info | Editar información personal |
| Edit shortcut for %@ | Editar atajo para %@ |
| Email address | Correo electrónico |
| Emergency contact | Contacto de emergencia |
| End may be cut off | Puede faltar el final |
| English | Inglés |
| Entertainment | Entretenimiento |
| Español | Español |
| Every phrase is banked | Todas las frases están grabadas |
| Explains how EchoVoice ranked these phrases | Explica cómo EchoVoice ordenó estas frases |
| Export | Exportar |
| Export Backup | Exportar respaldo |
| Export CSV | Exportar CSV |
| Export PDF | Exportar PDF |
| Export a PDF report or raw CSV data to review at your next appointment. Sample readings are left out. | Exporta un informe PDF o datos CSV para revisar en tu próxima cita. No se incluyen lecturas de ejemplo. |
| Export a PDF report or raw CSV data to review at your next speech therapy appointment. | Exporta un informe PDF o datos CSV para revisar en tu próxima cita de terapia del habla. |
| Export your voice recordings to keep forever. | Exporta tus grabaciones para conservarlas siempre. |
| Extra Large | Muy grande |
| Eye blend shapes | Gestos de los ojos |
| Eye control setup | Configurar control de mirada |
| Eye gaze | Mirada |
| Eye tracking tutorial complete! | ¡Completaste la guía de mirada! |
| Eye transforms | Movimiento de los ojos |
| Eyes (%@) | Ojos (%@) |
| FLAGGED | CAMBIO DETECTADO |
| Face lost | Cara fuera de vista |
| Face me | Hacia mí |
| Face not tracked | Cara no detectada |
| Face them | Hacia la otra persona |
| Face tracked | Cara detectada |
| Face tracked at %@ hertz | Cara detectada a %@ hercios |
| Family & friends | Familia y amistades |
| Fast | Rápido |
| Feelings | Sentimientos |
| Food & Drinks | Comida y bebidas |
| For HELP: blink five times quickly, then close your eyes and hold. | Para pedir AYUDA: parpadea cinco veces rápido y luego mantén los ojos cerrados. |
| For personal tracking only. EchoVoice does not diagnose or monitor a medical condition. | Solo para tu registro personal. EchoVoice no diagnostica ni vigila ninguna condición médica. |
| For recording phrases. | Para grabar frases. |
| Give me a moment. | Dame un momento. |
| HELP | AYUDA |
| HELP always has a button at the bottom of the board. Under hands-free control it needs a longer look, so it isn't chosen by accident. | El botón AYUDA siempre está al pie del tablero. Con el control sin manos requiere una mirada más larga para evitar activarlo sin querer. |
| HELP ready. Close your eyes and hold. | AYUDA preparada. Mantén los ojos cerrados. |
| HELP ready. Hold your eyes closed for 2 seconds to confirm. | AYUDA preparada. Cierra los ojos por 2 segundos para confirmar. |
| Hands-free | Sin manos |
| Hands-free control | Control sin manos |
| Hands-free conversation | Conversación sin manos |
| Hands-free guide | Guía sin manos |
| Hands-free off | Control sin manos apagado |
| Hands-free status | Estado del control sin manos |
| Head control needs a short setup | El control de cabeza necesita una breve configuración |
| Head control needs an iPhone or iPad with Face ID. On this device, use Touch. | El control de cabeza necesita un iPhone o iPad con Face ID. En este dispositivo, elige Tocar. |
| Head control needs its short setup (Settings) before it can select. Touch works now. | Configura el control de cabeza en Configuración para seleccionar. Ya puedes tocar la pantalla. |
| Head control on | Control de cabeza activo |
| Head control setup | Configurar control de cabeza |
| Head movement | Movimiento de cabeza |
| Head pose | Posición de la cabeza |
| Hear what someone says and get replies to it | Escucha lo que dice alguien y recibe respuestas sugeridas |
| Heard: “%@” | Se escuchó: «%@» |
| Hello! This is a preview of your speaking voice in EchoVoice. | ¡Hola! Así suena tu voz al hablar con EchoVoice. |
| Help | Ayuda |
| Hides the other tabs so the board can't be left by accident. Hold the lock for 1.5 seconds to unlock. | Oculta las otras pestañas para evitar salir del tablero sin querer. Mantén presionado el candado 1.5 segundos para desbloquear. |
| High Contrast | Alto contraste |
| Hold for 1.5 seconds to unlock caregiver settings | Mantén 1.5 segundos para desbloquear las opciones de cuidado |
| Hold still until the ring fills. %@ of %@ | No te muevas hasta que se llene el anillo. %@ de %@ |
| Hold the phone a little farther from your mouth. | Aleja un poco el teléfono de tu boca. |
| Hold the phone closer, about a hand's width away. | Acerca el teléfono, a una mano de distancia de tu boca. |
| Hold the top of your iPhone near the tag. | Acerca la parte superior de tu iPhone a la etiqueta. |
| Hold to speak | Mantener para hablar |
| Hold until it is chosen. Round %@ of %@ | Mantén la mirada hasta seleccionarlo. Ronda %@ de %@ |
| Hold your iPhone near a blank tag to save this phrase to it | Acerca tu iPhone a una etiqueta vacía para guardar esta frase |
| Hold your iPhone near a tag to hear its phrase | Acerca tu iPhone a una etiqueta para escuchar su frase |
| Hold your iPhone near the tag to save “%@”. | Acerca tu iPhone a la etiqueta para guardar «%@». |
| Hold... | Mantén... |
| Home | Casa |
| Home care | Cuidados en casa |
| How hands-free works | Cómo usar el control sin manos |
| How it works | Cómo funciona |
| How the threshold works | Cómo funciona el umbral |
| How will you choose? | ¿Cómo quieres elegir? |
| I | yo |
| I already made one | Ya creé una |
| I don't know | no sé |
| I don't like this | no me gusta esto |
| I don't understand | no entiendo |
| I don't want this | no quiero esto |
| I have a question | Tengo una pregunta |
| I have a question. | Tengo una pregunta. |
| I like this | me gusta esto |
| I love you | Te quiero |
| I love you. | Te quiero. |
| I need a break | Necesito descansar |
| I need a break. | Necesito descansar. |
| I need help breathing | Necesito ayuda para respirar |
| I need more time to answer. | Necesito más tiempo para responder. |
| I understand | entiendo |
| I want this | quiero esto |
| I want to go home | Quiero ir a casa |
| I want to play | quiero jugar |
| I want to tell you something. | Quiero contarte algo. |
| I want to watch | quiero ver |
| I'm Okay | Estoy bien |
| I'm Okay saved on this device | Estoy bien: guardado en este dispositivo |
| I'm in pain. | Tengo dolor. |
| I'm not sure. | No sé bien. |
| I'm okay | Estoy bien |
| I'm okay. | Estoy bien. |
| I'm sorry | lo siento |
| I'm thinking of you | estoy pensando en ti |
| I'm tired. | Siento cansancio. |
| ICON | ÍCONO |
| Icon %@ | Ícono %@ |
| If pointing isn't reliable | Si apuntar no funciona bien |
| Ignore quick repeat taps | Ignorar toques rápidos repetidos |
| Import | Importar |
| Import cancelled. | Importación cancelada. |
| In Settings, turn on Hands-free control and choose Head movement. Allow the camera when asked. | En Configuración, activa Control sin manos y elige Movimiento de cabeza. Permite usar la cámara cuando se te pida. |
| Interruptions without losing your thought | Interrupciones sin perder tu idea |
| It only ever learns from your own selections. There is no shared model and nothing is sent anywhere. | Solo aprende de tus propias selecciones. No hay un modelo compartido y no se envía nada. |
| It worked | Funcionó |
| JUST SAID | ACABO DE DECIR |
| January 1, 1970 | 1 de enero de 1970 |
| Journal | Diario |
| Just said: %@ | Acabo de decir: %@ |
| Keep It | Conservar |
| Keep a draft, use quick interjections, and retrieve personal shortcuts | Conserva un borrador, usa frases breves y recupera tus atajos |
| Keep a thought safe through interruptions | Conserva tu idea aunque te interrumpan |
| Keep mine | Dejar mi frase |
| Keep screen awake | Mantener pantalla encendida |
| Keep your eyes on the dot and turn your head toward it. | Mira el punto y gira la cabeza hacia él. |
| Keep your head still and move only your eyes to the dot. | Mantén la cabeza quieta y mueve solo los ojos hacia el punto. |
| Kept only while Listen is open. | Se conserva solo mientras Escuchar está abierto. |
| LOG PROBABILITIES | LOGARITMOS DE PROBABILIDAD |
| Label | Texto |
| Labelled, and left out of exports. | Están marcados y no se incluyen al exportar. |
| Large | Grande |
| Left | Izquierda |
| Left %@   Right %@   Up %@   Down %@ | Izq. %@   Der. %@   Arriba %@   Abajo %@ |
| Left–right | Izquierda–derecha |
| Level %.0f dBFS | Nivel %.0f dBFS |
| Listen | Escuchar |
| Listen needs microphone access. Allow it in iPhone Settings › EchoVoice. | Escuchar necesita acceso al micrófono. Actívalo en Configuración del iPhone › EchoVoice. |
| Listen needs speech recognition. Allow it in iPhone Settings › EchoVoice. | Escuchar necesita reconocimiento de voz. Actívalo en Configuración del iPhone › EchoVoice. |
| Listening on this device. Nothing is recorded or sent anywhere. | Escuchando en este dispositivo. No se guarda ni se envía audio. |
| Listening. No speech detected yet. | Escuchando. Aún no se detecta voz. |
| Listening… | Escuchando… |
| Live speech analysis | Análisis de voz en vivo |
| Live voice | Voz en vivo |
| Locked | Bloqueado |
| Look at five dots, one at a time. Keep your head still. | Mira cinco puntos, uno por uno. Mantén la cabeza quieta. |
| Look at the dot | Mira el punto |
| Look at the dot on %@ | Mira el punto en %@ |
| Look at the green tile | Mira el cuadro verde |
| Look at what you want. Needs a short setup and a steady phone position. | Mira lo que quieres. Requiere una breve configuración y una posición fija del teléfono. |
| Look to compose. Select Speak when ready. | Mira para escribir. Elige Hablar cuando termines. |
| Look-at point | Punto de mirada |
| Looking for your face | Buscando tu cara |
| Looking for your face. Face the screen in good light. | Buscando tu cara. Mira la pantalla con buena luz. |
| Loud | Ruidoso |
| Louder in noisy rooms | Más volumen con ruido |
| Loved one | Ser querido |
| Lower | Mínimo |
| MEASURED ON THIS DEVICE | MEDIDO EN ESTE DISPOSITIVO |
| Make EchoVoice easy to see and use. You can change these later in Settings. | Haz que EchoVoice sea fácil de ver y usar. Puedes cambiar esto en Configuración. |
| Make EchoVoice sound like you. | Haz que EchoVoice suene como tú. |
| Make it a full sentence | Completar la oración |
| Manage Phrase Cards (%@) | Administrar frases (%@) |
| Me:  | Yo:  |
| Medical conditions | Condiciones médicas |
| Medication names and doses | Nombres de medicamentos y dosis |
| Medications | Medicamentos |
| Mention to Clinician | Comentar en consulta |
| Message to speak | Mensaje para decir |
| Method | Método |
| Microphone | Micrófono |
| Microphone access is needed to bank this phrase. | Se necesita acceso al micrófono para guardar tu voz en esta frase. |
| Microphone access is needed to record your voice. | Se necesita acceso al micrófono para grabar tu voz. |
| Microphone is busy. If you're on a call, end it, then open Listen again. | El micrófono está ocupado. Si estás en una llamada, termínala y abre Escuchar de nuevo. |
| Moderate | Moderado |
| Money & Shopping | Dinero y compras |
| More hands-free options | Más opciones sin manos |
| More personal info | Más información personal |
| More settings | Más opciones |
| Move | Mover |
| Move %@ | Mover %@ |
| Move Down | Bajar |
| Move Up | Subir |
| Move a little back | Aléjate un poco |
| Move a little closer | Acércate un poco |
| Move a little closer to the phone. | Acércate un poco al teléfono. |
| Move a little further from the phone. | Aléjate un poco del teléfono. |
| Move back into the front camera's view. | Vuelve a colocarte frente a la cámara. |
| Move somewhere quieter, or turn off a fan or TV. | Busca un lugar más tranquilo o apaga el ventilador o la tele. |
| Move to Bottom | Mover al final |
| Move to Top | Mover al inicio |
| My address is | Mi dirección es |
| My allergies are | Mis alergias son |
| My date of birth is | Mi fecha de nacimiento es |
| My email address is | Mi correo electrónico es |
| My emergency contact is | Mi contacto de emergencia es |
| My medical conditions are | Mis condiciones médicas son |
| My medications are | Mis medicamentos son |
| My name is | Me llamo |
| My phone number is | Mi número de teléfono es |
| NFC Tags | Etiquetas NFC |
| NFC is disabled in this development build. Your other communication features are available. | NFC está desactivado en esta versión de desarrollo. Puedes usar las demás funciones de comunicación. |
| NFC isn't available here | NFC no está disponible aquí |
| NFC tag scanning requires a compatible physical iPhone. It isn't available on iPad or in Simulator. | Para leer etiquetas NFC necesitas un iPhone compatible. No funciona en iPad ni en el simulador. |
| Name | Nombre |
| Name and phone number | Nombre y teléfono |
| Needs a Face ID camera. Touch still works. | Necesita cámara Face ID. Puedes seguir tocando la pantalla. |
| Neither. | Ninguna de las dos opciones. |
| New Phrase | Nueva frase |
| Next | Siguiente |
| Next page | Página siguiente |
| Next phrases | Frases siguientes |
| Next topic | Tema siguiente |
| No | No |
| No Change Flagged | Sin cambios detectados |
| No Personal Voice found yet. Create one in Settings to hear phrases in your voice. | Aún no se encontró una voz personal. Crea una en Configuración para escuchar las frases con tu voz. |
| No message yet | Aún no hay mensaje |
| No personal baseline yet | Aún no hay una referencia personal |
| No reading in progress. | No hay una lectura en curso. |
| No readings yet | Aún no hay lecturas |
| No room reading yet. | Aún no se ha medido el ruido. |
| No speech heard | No se escuchó voz |
| Normal | Normal |
| Normal spread | Variación normal |
| Not a medical device. It does not diagnose or monitor any condition. | No es un dispositivo médico. No diagnostica ni vigila ninguna condición. |
| Not checked yet | Aún sin revisar |
| Not connected | Sin conectar |
| Not listening. | No está escuchando. |
| Not now | Ahora no |
| Nothing spoken recently | No has dicho nada recientemente |
| OK | Aceptar |
| Okay. | Está bien. |
| One moment | Un momento |
| Only phrase identifiers and counts are stored. Phrase text and recordings are never part of the model, and you can erase what it has learned in Settings. | Solo se guardan identificadores y conteos. El texto y las grabaciones no forman parte del modelo. Puedes borrar lo aprendido en Configuración. |
| Open Personal Voice | Abrir Voz personal |
| Open Settings | Abre Configuración |
| Open conversation workspace | Abrir espacio de conversación |
| Open conversation workspace, draft in progress | Abrir espacio de conversación, con borrador en curso |
| Open partner view | Abrir vista para acompañante |
| Opens EchoVoice and repeats the call for help aloud until someone stops it. | Abre EchoVoice y repite la petición de ayuda en voz alta hasta que alguien la detenga. |
| Opens EchoVoice and speaks one of your saved phrases, in your banked recording when there is one. | Abre EchoVoice y dice una de tus frases guardadas usando tu grabación si la hay. |
| Opens Messages with a help text ready to send | Abre Mensajes con una petición de ayuda lista para enviar |
| PERSONAL SHORTCUT (OPTIONAL) | ATAJO PERSONAL (OPCIONAL) |
| PICK A PHRASING | ELIGE CÓMO DECIRLO |
| PREVIEW | VISTA PREVIA |
| Page %@ of %@ | Página %@ de %@ |
| Partner view | Vista para acompañante |
| Patient: %@  •  Report Date: %@  •  Total Check-ins: %@ | Paciente: %@  •  Fecha: %@  •  Lecturas: %@ |
| Pause | Pausar |
| Pause Ratio | Pausas |
| Paused while EchoVoice speaks. | En pausa mientras EchoVoice habla. |
| Pausing | Pausas |
| Pausing %@ percent. | Pausas del %@ por ciento. |
| Pausing is %@%% of speech (usual amount: %@%%) | Las pausas ocupan el %@%% del habla (lo habitual: %@%%) |
| People & Family | Personas y familia |
| Permission denied. Allow EchoVoice access in iPhone Settings › Privacy & Security › Personal Voice. | No hay permiso. Dale acceso a EchoVoice en Configuración del iPhone › Privacidad y seguridad › Voz personal. |
| Permission granted! However, no Personal Voice was created on this iPhone yet. Create one in iPhone Settings › Accessibility › Personal Voice. | Ya diste permiso, pero aún no hay una voz personal en este iPhone. Crea una en Configuración del iPhone › Accesibilidad › Voz personal. |
| Permission not determined. Please tap Check for Personal Voice again. | Aún no se ha dado permiso. Toca Buscar voz personal de nuevo. |
| Personal | Personal |
| Personal Info | Información personal |
| Personal Information Phrases | Frases con información personal |
| Personal Shortcut | Atajo personal |
| Personal Voice is active — phrases speak in your voice. | La voz personal está activa: las frases usan tu voz. |
| Personal Voice isn’t available on this device. | La voz personal no está disponible en este dispositivo. |
| Personal phrase shortcuts | Atajos de frases personales |
| Phone & Technology | Teléfono y tecnología |
| Phone number | Número de teléfono |
| Phone positions | Posiciones del teléfono |
| Phrase | Frase |
| Phrase saved. | Frase guardada. |
| Phrases | Frases |
| Phrases Banked in Your Voice | Frases grabadas con tu voz |
| Pick one. You can change it later in Settings. | Elige una opción. Puedes cambiarla después en Configuración. |
| Pitch %@ hertz, pausing %@ percent. | Tono de %@ hercios, pausas del %@ por ciento. |
| Pitch Stability | Estabilidad del tono |
| Pitch stability | Estabilidad del tono |
| Places & Travel | Lugares y viajes |
| Play it back to be sure, then save. Once your voice changes, this recording can't be made again. | Escúchala para comprobar y luego guárdala. Si tu voz cambia, no podrás repetir esta grabación. |
| Play recording | Reproducir grabación |
| Please check my position. | Revisa mi posición, por favor. |
| Please explain that again. | Explícame eso otra vez, por favor. |
| Please repeat | Repite, por favor |
| Please repeat that. | Repite eso, por favor. |
| Please reposition me. | Cámbiame de posición, por favor. |
| Please stay with me. | Quédate conmigo, por favor. |
| Point at the dot on %@ | Apunta al punto en %@ |
| Point at the green tile | Apunta al cuadro verde |
| Point with | Apuntar con |
| Point with small head movements. The steadiest choice for most people. | Apunta con pequeños movimientos de cabeza. La opción más estable para la mayoría. |
| Point your nose at five dots, one at a time. | Apunta la nariz a cinco puntos, uno por uno. |
| Point your nose at the dot | Apunta la nariz al punto |
| Position | Posición |
| Position name | Nombre de la posición |
| Prepare for a situation | Prepárate para una situación |
| Preview | Vista previa |
| Preview Voice | Probar voz |
| Previous | Anterior |
| Previous page | Página anterior |
| Previous phrases | Frases anteriores |
| Previous topic | Tema anterior |
| Put the phone where it will stay, at eye level if you can. | Coloca el teléfono donde lo usarás, a la altura de los ojos si puedes. |
| Question | Pregunta |
| Quick | Rápidas |
| Quiet | Tranquilo |
| REVERSED vs docs | INVERSO a documentación |
| Re-center | Centrar |
| Re-center previews | Centrar vistas previas |
| Re-centered. | Centrado de nuevo. |
| Re-centering. Keep still for a moment. | Centrando de nuevo. No te muevas un momento. |
| Re-record | Volver a grabar |
| Read aloud | Lee en voz alta |
| Ready. | Listo. |
| Recent messages | Mensajes recientes |
| Record | Grabar |
| Record %@ in your own voice | Grabar %@ con tu propia voz |
| Record Phrase | Grabar frase |
| Record Voice | Grabar voz |
| Record a phrase | Grabar una frase |
| Record again | Grabar de nuevo |
| Record at least one phrase first. | Primero graba al menos una frase. |
| Record phrases you use often. | Graba las frases que usas más. |
| Record these while they still sound like you | Graba estas frases con tu voz de hoy |
| Recording ready. Play it back, then save. | Grabación lista. Escúchala y luego guárdala. |
| Recording them means they'll play back in your real voice instead of a synthetic one. | Al grabarlas, se reproducirán con tu voz real en lugar de una voz sintética. |
| Recording... %.1fs | Grabando... %.1fs |
| Records that you're okay | Guarda que estás bien |
| Remove | Quitar |
| Remove phrase | Quitar frase |
| Remove sample readings | Quitar lecturas de ejemplo |
| Remove “%@” | Quitar «%@» |
| Removed “%@” | Se quitó «%@» |
| Replaces your message with this wording. It is not spoken until you press Speak. | Reemplaza tu mensaje con esta frase. Solo se dice cuando presionas Hablar. |
| Replies | Respuestas |
| Replies speak immediately and keep your draft. | Las respuestas se dicen al instante y conservan tu borrador. |
| Requires iOS 26 or later. | Requiere iOS 26 o posterior. |
| Reset learned suggestions | Borrar sugerencias aprendidas |
| Rest the cursor here | Deja el cursor aquí |
| Rest the cursor on a button until its ring fills. | Deja el cursor sobre un botón hasta que se llene el anillo. |
| Rest the cursor on a button. A ring fills in %.1f seconds, then it is chosen. Look away before it fills to cancel. | Deja el cursor sobre un botón. El anillo se llena en %.1f segundos y lo selecciona. Mira a otro lado antes de que se llene para cancelar. |
| Restored  | Se restauró:  |
| Resume | Continuar |
| Right | Derecha |
| Run direction test | Probar direcciones |
| Run setup again | Repetir configuración inicial |
| SPOKEN SENTENCE | FRASE PARA DECIR |
| Sample reading — not recorded by you | Lectura de ejemplo: no es tu grabación |
| Save | Guardar |
| Save Anyway | Guardar de todos modos |
| Save this position | Guardar esta posición |
| Save to Phrase Bank | Guardar en banco de frases |
| Saved on this device | Guardado en este dispositivo |
| Saved only on this device | Se guarda solo en este dispositivo |
| Saved only on this phone | Se guarda solo en este teléfono |
| Saved: building your personal baseline | Guardado: creando tu referencia personal |
| Saved: your reading looks steady | Guardado: tu lectura parece estable |
| Say this clearly, close to the phone: | Di esto con claridad, cerca del teléfono: |
| Scan a tag | Leer etiqueta |
| Scan a tag you've already set up to hear it speak. | Lee una etiqueta que ya configuraste para escuchar su frase. |
| Scan an NFC tag | Leer etiqueta NFC |
| Scroll down | Bajar |
| Scroll up | Subir |
| Selection check | Prueba de selección |
| Selection check saved on this device. | Prueba de selección guardada en este dispositivo. |
| Selection paused. Look at Resume to continue. | Selección en pausa. Mira Continuar para seguir. |
| Set Up Personal Info | Configurar información personal |
| Set it up | Configúralo |
| Set up | Configurar |
| Set up again | Configurar de nuevo |
| Set up again for this position | Configura de nuevo para esta posición |
| Set up again for this position. | Configura de nuevo para esta posición. |
| Set up and checked. | Configurado y revisado. |
| Set up hands-free | Configurar control sin manos |
| Set up head control (1 minute) | Configurar control de cabeza (1 minuto) |
| Set up. | Configurado. |
| Settings | Configuración |
| Setup | Configuración inicial |
| Setup and checks | Configuración y pruebas |
| Setup didn't finish | No se completó la configuración |
| Setup done — check or redo | Ya configurado: revisar o repetir |
| Setup needed | Falta configurar |
| Setup saved, but some directions did not follow. Try setting up again. | Configuración guardada, pero algunas direcciones no respondieron. Intenta configurar de nuevo. |
| Setup saved. The cursor follows you in every direction. | Configuración guardada. El cursor te sigue en todas las direcciones. |
| Share as Audio Files | Compartir archivos de audio |
| Shares each recording as an ordinary audio file named after its phrase, to keep anywhere | Comparte cada grabación como un archivo de audio con el nombre de su frase para guardarlo donde quieras |
| Shortcut | Atajo |
| Show all suggested phrases | Mostrar todas las frases sugeridas |
| Show symbols | Mostrar símbolos |
| Show symbols on Quick phrases | Mostrar símbolos en frases rápidas |
| Show the math | Ver los cálculos |
| Show tracking readout on the board | Mostrar datos de seguimiento en el tablero |
| Showing sample readings | Se muestran lecturas de ejemplo |
| Shows your message in large type for the person you are talking to | Muestra tu mensaje en letra grande para la persona con quien hablas |
| Signal check | Prueba de señal |
| Sit the way you usually sit. | Siéntate como lo haces normalmente. |
| Situation | Situación |
| Slow | Lento |
| Smart Suggestions | Sugerencias inteligentes |
| Social & Repair | Conversar y aclarar |
| Some directions failed. Set up again. | Fallaron algunas direcciones. Configura de nuevo. |
| Space | Espacio |
| Speak | Hablar |
| Speak ${phrase} | Decir ${phrase} |
| Speak %@ | Decir %@ |
| Speak a Phrase | Decir una frase |
| Speak draft | Decir borrador |
| Speak message | Decir mensaje |
| Speaking | Hablando |
| Speaking Rate | Velocidad |
| Speaking out loud so someone nearby can hear. | Hablando en voz alta para que alguien cerca escuche. |
| Speaking rate | Velocidad del habla |
| Speaking rate is %@ words/min (usual pace: %@ words/min) | La velocidad es de %@ palabras/min (tu ritmo habitual: %@ palabras/min) |
| Speaking rate over time | Velocidad del habla con el tiempo |
| Speaking: “%@” | Diciendo: «%@» |
| Speaks this phrase aloud | Dice esta frase en voz alta |
| Speaks this repair phrase and keeps your draft | Dice esta frase para aclarar y conserva tu borrador |
| Speech Rate & Volume | Velocidad y volumen de voz |
| Speech Speed | Velocidad de voz |
| Speech recognition caught %@%% of the sentence (usually %@%%) | El reconocimiento captó el %@%% de la oración (lo habitual: %@%%) |
| Spell | Deletrear |
| Sports & Hobbies | Deportes y pasatiempos |
| Standard | Estándar |
| Start Using EchoVoice | Empezar a usar EchoVoice |
| Start listening | Empezar a escuchar |
| Start may be cut off | Puede faltar el inicio |
| Start recording | Empezar a grabar |
| Start setup | Empezar |
| Statement | Comentario |
| Status | Estado |
| Status unknown. | Estado desconocido. |
| Stay on Speak screen | Permanecer en Hablar |
| Steady compared with your usual readings | Estable respecto a tus lecturas habituales |
| Still writing — please wait | Sigo escribiendo, espera por favor |
| Stop | Detener |
| Stop Recording | Detener grabación |
| Stop calling for help | Dejar de pedir ayuda |
| Stop recording | Detener grabación |
| Stop speaking | Dejar de hablar |
| Stop voice | Detener voz |
| Stops speaking and closes this screen | Deja de hablar y cierra esta pantalla |
| Suggested | Sugeridas |
| Suggested phrases | Frases sugeridas |
| Suggested: %@ | Sugerida: %@ |
| Suggests complete sentences using only the words you chose. You pick one. | Sugiere oraciones completas usando solo las palabras que elegiste. Tú eliges una. |
| TV | Tele |
| Tag recognized. | Etiqueta reconocida. |
| Tag saved. | Etiqueta guardada. |
| Tag saved. Tap it any time to speak this phrase. | Etiqueta guardada. Tócala cuando quieras para decir esta frase. |
| Tags | Etiquetas |
| Tap Record when ready | Toca Grabar cuando quieras empezar |
| Tap Set up hands-free. Follow five dots, then EchoVoice checks that the cursor goes where you point. | Toca Configurar control sin manos. Sigue cinco puntos; luego EchoVoice revisará que el cursor siga hacia donde apuntas. |
| Tap a phrase or type your own. | Toca una frase o escribe la tuya. |
| Tap a phrase. Let EchoVoice speak for you. | Toca una frase. Deja que EchoVoice hable por ti. |
| Tap here to practice | Toca aquí para practicar |
| Tap record on any phrase below to record in your real voice. | Toca Grabar en cualquier frase de abajo para usar tu voz real. |
| Tap to Speak | Toca para hablar |
| Tap what you want. The camera stays off. | Toca lo que quieres. La cámara permanece apagada. |
| Target | Objetivo |
| Target tile | Cuadro objetivo |
| Test a tag | Probar etiqueta |
| Text | Mensaje |
| Text Size | Tamaño del texto |
| Thank you. | Gracias. |
| That backup contained no restorable phrases. | Ese respaldo no contenía frases para restaurar. |
| That check-in couldn't be saved. Please try again. | No se pudo guardar esta lectura. Intenta de nuevo. |
| That doesn't look like an EchoVoice message bank. | Ese archivo no parece ser un banco de mensajes de EchoVoice. |
| That recording was too short. Please record the whole phrase. | La grabación fue muy corta. Graba la frase completa. |
| That recording was too short. Read the full sentence, then tap stop. | La grabación fue muy corta. Lee toda la oración y toca Detener. |
| That shortcut is already in use or too long. | Ese atajo ya se usa o es muy largo. |
| That tag can't store EchoVoice data. | Esa etiqueta no puede guardar datos de EchoVoice. |
| That tag is locked and can't be changed. | Esa etiqueta está bloqueada y no se puede cambiar. |
| That tag is too small — it holds %@ bytes but needs %@. | Esa etiqueta es muy pequeña: caben %@ bytes, pero se necesitan %@. |
| That tag isn't NDEF formatted. | Esa etiqueta no tiene formato NDEF. |
| That tag isn't an EchoVoice tag. | Esa etiqueta no es de EchoVoice. |
| That tag isn't supported. | Esa etiqueta no es compatible. |
| That's not what I meant. | Eso no es lo que quise decir. |
| That’s not what I meant | Eso no es lo que quise decir |
| The dots didn't line up in order. Keep your head still and look right at each dot until its ring fills. | Los puntos no quedaron en orden. Mantén la cabeza quieta y mira cada punto hasta que se llene su anillo. |
| The dots didn't line up in order. Point your nose at each dot and hold until its ring fills. | Los puntos no quedaron en orden. Apunta la nariz a cada punto hasta que se llene su anillo. |
| The on-device model is still downloading. | El modelo del dispositivo aún se está descargando. |
| Then EchoVoice checks that the cursor goes where you look. | Después, EchoVoice revisará que el cursor siga tu mirada. |
| These become one-tap phrases. Skip any you like. | Se convierten en frases de un toque. Puedes omitir lo que quieras. |
| These were generated to demonstrate the journal. They are excluded from clinician exports. | Se generaron para mostrar cómo funciona el diario. No se incluyen en los informes para consulta. |
| They | La otra persona |
| They said | La otra persona dijo |
| They:  | La otra persona:  |
| Thinking… | Pensando… |
| This device can't recognize speech on its own, so Listen stays off. EchoVoice never sends audio to a server. | Este dispositivo no puede reconocer voz en tu idioma sin conexión. Escuchar permanecerá apagado. EchoVoice nunca envía audio a un servidor. |
| This device doesn't support Apple Intelligence. | Este dispositivo no admite Apple Intelligence. |
| This device doesn't support NFC tags. | Este dispositivo no admite etiquetas NFC. |
| This phrase is already saved. | Esta frase ya está guardada. |
| This reading came before you had %@ earlier ones to compare against, so it was saved without being judged. Comparing against fewer readings would mostly react to ordinary variation. | Esta lectura se hizo antes de tener %@ lecturas previas para comparar, así que se guardó sin evaluar cambios. Con menos lecturas, la comparación reflejaría sobre todo variaciones normales. |
| Tile | Cuadro |
| Time & Weather | Tiempo y clima |
| To cancel, look at Stop. | Para cancelar, mira Detener. |
| To create your Personal Voice, open Settings › Accessibility › Personal Voice. Then return here and allow EchoVoice to use it. | Para crear tu voz personal, abre Configuración › Accesibilidad › Voz personal. Luego regresa aquí y permite que EchoVoice la use. |
| Touch | Tocar |
| Touch always works, and the HELP button is always on screen. For scanning instead of pointing, turn on iOS Switch Control (Settings › Accessibility › Switch Control): it steps through EchoVoice's buttons and selects with a switch, a tap anywhere, or a head turn. | Siempre puedes tocar la pantalla y el botón AYUDA siempre está visible. Para recorrer los botones, activa Control por botón en iOS (Configuración › Accesibilidad › Control por botón). Puedes elegir con un botón, un toque en cualquier lugar o un giro de cabeza. |
| Touch works here too. Turn on hands-free control in Settings to use gaze. | También puedes tocar aquí. Activa el control sin manos en Configuración para usar la mirada. |
| Tracking diagnostics | Diagnóstico de seguimiento |
| Tracking is weak | Señal débil |
| Tracking is weak. More light usually helps. | La señal es débil. Más luz suele ayudar. |
| Tracking was too shaky. Steady the phone — a stand or mount helps — and check the lighting. | La señal fue inestable. Fija el teléfono con un soporte y revisa la luz. |
| Try again | Intentar de nuevo |
| Try it | Pruébalo |
| Try selecting | Probar selección |
| Turn it on | Actívalo |
| Turn on Apple Intelligence in Settings to use this. | Activa Apple Intelligence en Configuración para usar esto. |
| Turn on hands-free control in Settings first. | Primero activa el control sin manos en Configuración. |
| Turn pages with the arrows, or close your eyes and hold. | Cambia de página con las flechas o mantén los ojos cerrados. |
| Turn the page | Cambia de página |
| Turn your head toward the dot | Gira la cabeza hacia el punto |
| Tutorial | Guía |
| Type | Escribir |
| Type a message | Escribe un mensaje |
| Type a shortcut or phrase label | Escribe un atajo o el nombre de una frase |
| Type this short cue in the Conversation workspace to retrieve the exact sentence. It stays on this device. | Escribe este atajo en el espacio de conversación para recuperar la frase exacta. Se guarda en este dispositivo. |
| Undo | Deshacer |
| Until then, looking will not select anything. | Hasta entonces, mirar no seleccionará nada. |
| Up | Arriba |
| Upper | Máximo |
| Up–down | Arriba–abajo |
| Use the arrow buttons at the bottom of the board. | Usa las flechas al pie del tablero. |
| Use the arrow buttons, or close your eyes and hold for a second. | Usa las flechas o cierra los ojos por un segundo. |
| Use your voice | Usa tu voz |
| Very quiet | Muy bajo |
| Voice | Voz |
| Voice Banking Studio | Estudio de voz |
| Voice Journal | Diario de voz |
| Voice Journal sample data | Datos de ejemplo del diario de voz |
| Voice options | Opciones de voz |
| Voice recording | Grabación de voz |
| Voice steadiness | Estabilidad de la voz |
| Voice steadiness has changed since your recent readings | La estabilidad de tu voz cambió desde tus últimas lecturas |
| Volume | Volumen |
| Volume is at 100%, so it can't go louder. | El volumen está al 100%, no puede subir más. |
| Wait a beat after speaking before tapping Stop. | Al terminar de hablar, espera un momento antes de tocar Detener. |
| Welcome to EchoVoice | Te damos la bienvenida a EchoVoice |
| When the sunlight strikes raindrops in the air, they act as a prism and form a rainbow. | Cuando la luz del sol atraviesa las gotas de lluvia, estas actúan como un prisma y forman un arcoíris. |
| Why these suggestions? | ¿Por qué estas sugerencias? |
| Why these? | ¿Por qué estas? |
| Why? | ¿Por qué? |
| Words | Palabras |
| Words per minute | Palabras por minuto |
| Words understood | Palabras entendidas |
| Works now. Setup makes it more accurate. | Ya funciona. Configurarlo mejora la precisión. |
| Worth Discussing | Para comentar |
| Worth another take | Conviene grabar de nuevo |
| Worth mentioning to your clinician | Conviene comentarlo en tu consulta |
| Write %@ to a tag | Guardar %@ en una etiqueta |
| Write a phrase to a tag | Guardar una frase en una etiqueta |
| Write to tag | Escribir etiqueta |
| Writing a message… | Escribiendo un mensaje… |
| Writing more replies | Escribiendo más respuestas |
| Writing options on this device… | Escribiendo opciones en este dispositivo… |
| Writing sentence options on this device | Escribiendo opciones de oración en este dispositivo |
| Written on this device from your words only. Nothing is sent anywhere. | Se escribió en este dispositivo solo con tus palabras. No se envía nada. |
| Yes | Sí |
| Yes/no question | Pregunta de sí o no |
| You | Tú |
| Your Own Voice | Tu propia voz |
| Your Personal Voice is ready | Tu voz personal está lista |
| Your Voice | Tu voz |
| Your message appears here | Tu mensaje aparece aquí |
| Your name | Tu nombre |
| Your own voice | Tu propia voz |
| Your past readings were unusually close together, so EchoVoice used a minimum spread of %@ instead. Without it, ordinary week-to-week variation would look like a large change. | Tus lecturas anteriores eran muy parecidas, así que EchoVoice usó una variación mínima de %@. Sin ella, los cambios normales de una semana a otra parecerían grandes. |
| Your phrase wasn't saved. Please try again. | Tu frase no se guardó. Intenta de nuevo. |
| Your previous setup, if any, is unchanged. | Tu configuración anterior, si la había, sigue igual. |
| Your readings have shifted over your last few check-ins. A phrase recorded today preserves how you sound today — that recording doesn't change later. | Tus lecturas han cambiado últimamente. Al grabar una frase hoy, conservas cómo suena tu voz hoy. Esa grabación ya no cambia. |
| Your recent readings are holding steady. A phrase recorded today preserves how your voice sounds today. | Tus últimas lecturas están estables. Al grabar una frase hoy, conservas cómo suena tu voz hoy. |
| Your setup | Tu configuración |
| Your usual | Tu nivel habitual |
| Your voice | Tu voz |
| Your voice is steady — a good time to record | Tu voz está estable: es buen momento para grabar |
| afraid | con miedo |
| after | después |
| after “%@” | después de «%@» |
| afternoon | la tarde |
| again | otra vez |
| airport | aeropuerto |
| all | todo |
| all done | ya terminé |
| am | soy |
| and | y |
| angry | con enojo |
| answer | contestar |
| appointment | cita |
| are | eres |
| arm blinks | parpadeos para preparar |
| art | arte |
| as documented | según documentación |
| away | lejos |
| bad | mal |
| baseball | béisbol |
| basketball | básquetbol |
| bathroom | baño |
| be | ser |
| bed | cama |
| bedroom | recámara |
| before | antes |
| big | grande |
| blanket | cobija |
| blue | azul |
| book | libro |
| breakfast | desayuno |
| bus | camión |
| but | pero |
| buy | comprar |
| calendar | calendario |
| calibrated | calibrado |
| call | llamar |
| call my caregiver | llama a quien me cuida |
| call my family | llama a mi familia |
| call them | llámales |
| calm | con calma |
| can | puedo |
| cancel | cancelar |
| car | carro |
| card | tarjeta |
| caregiver | quien me cuida |
| cash | efectivo |
| chair | silla |
| change | cambiar |
| channel | canal |
| charger | cargador |
| checked on this device in %.0f ms | revisado en este dispositivo en %.0f ms |
| child | hijo o hija |
| clinic | clínica |
| close | cerrar |
| close it | ciérralo |
| closed | cerrados |
| closer | más cerca |
| cloudy | nublado |
| coffee | café |
| cold | frío |
| come | venir |
| comfortable | a gusto |
| computer | computadora |
| confused | siento confusión |
| cool | fresco |
| cursor | cursor |
| custom | personalizado |
| default | predeterminado |
| default mapping | mapeo predeterminado |
| did | hice |
| did not follow | no siguió |
| different | diferente |
| dinner | cena |
| distance | distancia |
| do | hacer |
| doctor | doctor |
| don't | no quiero |
| door | puerta |
| down | abajo |
| drink | beber |
| dwell | mirada |
| e.g. Can you play some music? | Ej.: ¿Puedes poner música? |
| e.g. Music | Ej.: Música |
| e.g. app | Ej.: cita |
| e.g. mus | Ej.: mus |
| eat | comer |
| emergency | emergencia |
| evening | la noche |
| excuse me | con permiso |
| eyes | ojos |
| eyes closed | ojos cerrados |
| family | familia |
| fan | ventilador |
| farther | más lejos |
| fast | rápido |
| feel | siento |
| find | encontrar |
| finish | terminar |
| finished | terminé |
| flagged | cambio detectado |
| football | fútbol americano |
| for | para |
| forest | verde bosque |
| friend | amigo |
| frustrated | con frustración |
| games | juegos |
| gardening | jardinería |
| get | conseguir |
| give me more time | dame más tiempo |
| go | ir |
| golf | golf |
| good | bien |
| goodbye | adiós |
| grandchild | nieto o nieta |
| green | verde |
| happy | feliz |
| have | tengo |
| he | él |
| head motion | movimiento de cabeza |
| hello | hola |
| help | ayuda |
| here | aquí |
| hold eyes closed | mantén los ojos cerrados |
| home | casa |
| hospital | hospital |
| hot | caliente |
| how | cómo |
| how are you? | ¿cómo estás? |
| how much? | ¿cuánto cuesta? |
| how often you use it at all | qué tanto la usas en total |
| how was your day? | ¿cómo te fue hoy? |
| hungry | tengo hambre |
| hurt | me duele |
| in | en |
| internet | internet |
| it | eso |
| it's something else | es otra cosa |
| Allow speech recognition in Settings to measure words understood. You can still record. | Permite el reconocimiento de voz en Configuración para medir las palabras entendidas. Puedes seguir grabando. |
| Words understood couldn't be measured. Your check-in was saved; try again next time. | No se pudo medir cuántas palabras se entendieron. Tu lectura se guardó; intenta de nuevo la próxima vez. |
| On-device speech recognition isn't available in your language. You can still record; words understood won't be scored. | El reconocimiento de voz sin conexión no está disponible en tu idioma. Puedes grabar, pero no se medirá cuántas palabras se entendieron. |
| juice | jugo |
| kitchen | cocina |
| know | saber |
| later | después |
| lavender | lavanda |
| left | izquierda |
| less | menos |
| light | luz |
| like | me gusta |
| lime | verde lima |
| listen | escuchar |
| Listen couldn't recognize speech on this device. Check that on-device recognition for your language is available, then try again. No audio was sent. | Escuchar no pudo reconocer voz en este dispositivo. Revisa que el reconocimiento sin conexión esté disponible en tu idioma e intenta de nuevo. No se envió audio. |
| little | pequeño |
| lonely | siento soledad |
| look | mirar |
| love | cariño |
| lunch | comida |
| mad | con enojo |
| make | hacer |
| mapping | mapeo |
| matches your board: %@ | coincide con tu tablero: %@ |
| medication | medicamento |
| mine | mío |
| mode | modo |
| money | dinero |
| more | más |
| morning | la mañana |
| move | mover |
| movie | película |
| music | música |
| my favorite | mi favorito |
| need | necesito |
| needs setup | falta configurar |
| new | nuevo |
| news | noticias |
| night | la madrugada |
| no | no |
| no clipping | sin distorsión |
| no conversation context to use | no hay contexto de conversación |
| no reading | sin lectura |
| no signal | sin señal |
| no, but... | no, pero... |
| not | no |
| now | ahora |
| nurse | enfermera |
| of %@ | de %@ |
| off | apagado |
| old | viejo |
| on | encendido |
| one | uno |
| open | abiertos |
| open it | ábrelo |
| orange | naranja |
| out | fuera |
| outdoors | al aire libre |
| outside | afuera |
| pain | dolor |
| parent | mamá o papá |
| partner | pareja |
| pause | pausa |
| pay | pagar |
| pharmacy | farmacia |
| phone | teléfono |
| photography | fotografía |
| pillow | almohada |
| pitch | tono |
| plain | neutro |
| play | jugar |
| please | por favor |
| please explain | explícame, por favor |
| please reposition me | cámbiame de posición, por favor |
| please say it another way | dilo de otra manera, por favor |
| please say that again | repite eso, por favor |
| please wait | espera, por favor |
| pretty | bonito |
| previous phrase | frase anterior |
| price | precio |
| purple | morado |
| put | poner |
| raining | está lloviendo |
| rate | frecuencia |
| read | leer |
| reading | lectura |
| ready | ya puedo empezar |
| receipt | recibo |
| red | rojo |
| remote | control remoto |
| reschedule | cambiar la cita |
| restaurant | restaurante |
| %@ phrases with saved wording | %@ frases con texto guardado |
| 1 phrase with saved wording | 1 frase con texto guardado |
| %@ recordings | %@ grabaciones |
| 1 recording | 1 grabación |
| right | derecha |
| rose | rosa |
| sad | triste |
| same | igual |
| say | decir |
| school | escuela |
| see | ver |
| selecting | seleccionando |
| send a message | manda un mensaje |
| she | ella |
| shopping | compras |
| sibling | hermano o hermana |
| sick | me siento mal |
| signal | señal |
| sitUp | sentarme |
| sky | azul cielo |
| slow | lento |
| slowly | despacio |
| %@ on-device suggestions | %@ sugerencias del dispositivo |
| 1 on-device suggestion | 1 sugerencia del dispositivo |
| snack | algo de comer |
| soccer | fútbol |
| some | algo de |
| something else | otra cosa |
| sports | deportes |
| spouse | esposo o esposa |
| start | empezar |
| state | estado |
| stay with me | quédate conmigo |
| stop | parar |
| store | tienda |
| suction | aspiración |
| sunny | soleado |
| tablet | tableta |
| take | tomar |
| tap a point | toca un punto |
| tea | té |
| television | televisión |
| tell | contar |
| tell them | diles |
| text | mensaje de texto |
| thank you | gracias |
| that | eso |
| that is not what I meant | eso no es lo que quise decir |
| the bottom | la parte de abajo |
| the last phrase | la última frase |
| the left | la izquierda |
| the middle | el centro |
| the right | la derecha |
| the top | la parte de arriba |
| therapist | terapeuta |
| therapy | terapia |
| there | allá |
| they | ellos |
| think | pensar |
| thirsty | tengo sed |
| this | esto |
| this reading | esta lectura |
| time | vez |
| time of day | momento del día |
| times | veces |
| tired | con cansancio |
| today | hoy |
| tomorrow | mañana |
| too cold | demasiado frío |
| too expensive | muy caro |
| too hot | demasiado caliente |
| turn | girar |
| turn it off | apágalo |
| turn it on | préndelo |
| tv | tele |
| uncomfortable | con incomodidad |
| under | debajo |
| up | arriba |
| video call | videollamada |
| visit me | ven a verme |
| volume down | baja el volumen |
| volume up | sube el volumen |
| wait | esperar |
| want | quiero |
| was | era |
| water | agua |
| we | nosotros |
| were | eran |
| what | qué |
| what time? | ¿qué hora? |
| what usually follows | lo que suele seguir |
| what's new? | ¿qué hay de nuevo? |
| when | cuándo |
| when? | ¿cuándo? |
| where | dónde |
| where are we? | ¿dónde estamos? |
| who | quién |
| who is calling? | ¿quién llama? |
| why | por qué |
| will | voy a |
| window | ventana |
| with | con |
| without | sin |
| words/min | palabras/min |
| work | trabajo |
| works | funciona |
| worried | con preocupación |
| wpm | palabras/min |
| write | escribir |
| yellow | amarillo |
| yes | sí |
| yes, but... | sí, pero... |
| yesterday | ayer |
| you | tú |
| you're welcome | de nada |
| your usual range | tu rango habitual |
| yum | qué rico |
| “%@” | “%@” |
| “%@” will go back to the computer voice. You can undo this for 10 seconds. | «%@» volverá a usar la voz sintética. Puedes deshacer esto durante 10 segundos. |
| • %@ | • %@ |
| ✓ Apple Personal Voice '%@' is active! | ¡La voz personal de Apple «%@» está activa! |

### InfoPlist.xcstrings

| English / source | Spanish |
| --- | --- |
| EchoVoice reads and writes NFC tags so you can place a tag anywhere in your home and tap it to speak a phrase in your own voice. | EchoVoice lee y escribe etiquetas NFC para que pongas una etiqueta en tu casa y la toques para decir una frase con tu propia voz. |
| EchoVoice uses the front camera to follow your head or eyes so you can choose phrases hands-free. Camera images are processed on this device and are never saved or sent anywhere. | EchoVoice usa la cámara frontal para seguir tu cabeza o tus ojos y elegir frases sin usar las manos. Las imágenes se procesan en este dispositivo; nunca se guardan ni se envían. |
| EchoVoice records phrases in your own voice so you can speak them later. In Listen mode it hears your conversation partner so it can suggest replies, and it can measure how loud the room is to adjust speaking volume. Nothing is sent anywhere. | EchoVoice graba frases con tu voz para decirlas después. En Escuchar, oye a la otra persona para sugerir respuestas. También puede medir el ruido del lugar para ajustar el volumen. No se envía nada. |
| During a voice journal check-in, EchoVoice checks how much of the practice sentence was understood. In Listen mode, it turns what your conversation partner says into text so it can suggest replies. Recognition runs entirely on this device, and audio is never stored or sent anywhere. | En el diario de voz, EchoVoice revisa cuánto se entendió de la oración de práctica. En Escuchar, convierte lo que dice la otra persona en texto para sugerir respuestas. Todo se reconoce en este dispositivo. El audio nunca se guarda ni se envía. |

### AppShortcuts.xcstrings

| English / source | Spanish |
| --- | --- |
| ${applicationName} help | ${applicationName} ayuda |
| Call for help with ${applicationName} | Pedir ayuda con ${applicationName} |
| I need help with ${applicationName} | Necesito ayuda con ${applicationName} |
| Say something with ${applicationName} | Decir algo con ${applicationName} |
| Speak with ${applicationName} | Hablar con ${applicationName} |
