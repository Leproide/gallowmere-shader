<!--
  Gallowmere - README
  Author: https://github.com/Leproide
  License: GPL-3.0-or-later
-->

# Gallowmere

Shader per [MediEvilRecomp ITA](https://github.com/Leproide/MediEvilRecomp-ITA) che usa i dati veri del rendering del gioco invece di stimarli dall'immagine finale.

[![MediEvilRecomp ITA - video](https://img.youtube.com/vi/cfNv3-evlD4/maxresdefault.jpg)](https://youtu.be/cfNv3-evlD4)

**Cosa fa:** luce del gioco con occlusione ambientale, luna e luci puntiformi calcolate sulle normali vere, ombre per la luna e la luce principale, fiamme che tremolano, riflessi su armi, scudi e acqua, nebbia di distanza e foschia a terra, raggi di luna, bloom.

## Installazione

È lo shader predefinito di MediEvilRecomp ITA dalla v1.1.16: è incluso nei pacchetti delle release, viene scaricato dagli script di prima compilazione e al primo avvio viene selezionato da solo. Si trova anche nel Mod Hub del fork: **Mods → Explore Mod Hub → Gallowmere**. Si sceglie o si spegne dal menu **Shaders**. Richiede **Better rendering** attivo.

A mano: copia la cartella del repository in `shaders/gallowmere-shader/` accanto all'eseguibile.

## Requisiti

- MediEvilRecomp ITA v1.1.16 o successiva, con le correzioni di RecompOne in `recompone-fixes/` (applicate dagli script di prima compilazione e dalle release):
  - `shader-gbuffer.patch`: oltre all'immagine RecompOne scrive **Albedo** (il colore della texture, senza la luce dei vertici) e **Shading** (il colore dei vertici, cioè la luce "cotta" del gioco con 0.5 = neutro, e l'id del triangolo);
  - `effect-lights.patch`: gli effetti luminosi in 3D (fuoco, magie) diventano luci puntiformi;
  - `material-picker.patch`: selettore dei materiali delle texture (Development mode del fork).
- Renderer OpenGL 3.3 o superiore (non il renderer legacy).

Senza le correzioni lo shader lascia l'immagine del gioco com'è.

## Materiali

Il gioco non dice di che materiale è una superficie. Il fork passa allo shader i materiali delle texture (`patches/render/MaterialTags.cs`):
- armatura di Dan, armi, cancelli e grate sono metallo fisso (si spengono con **Default materials** in Misc → Quality of life);
- con **Development mode** si marcano altre texture (metallo, vetro, bagnato, acqua, luminoso, pietra, legno) cliccandole in gioco.

Il resto del metallo lo stima lo shader dal colore (**Guess metal from colour**), solo sulle texture senza marcature.

## Come funziona

| Passo | File | Cosa fa |
|---|---|---|
| 0 | `atmos.slang` | dati della scena mediati nel tempo: colore del cielo (base della nebbia), apertura (interno o esterno), limite di disegno, vuoto sotto l'orizzonte, presenza della scena 3D |
| 1 | `emit.slang` | luce degli effetti: dove il gioco ha disegnato un effetto luminoso sopra una superficie (fonti di vita, magie) la differenza è luce emessa |
| 2 | `emitters.slang` | raccoglie quella luce in 16×9 celle con la loro posizione 3D: diventano luci puntiformi |
| 3 | `surface.slang` | normale vera di ogni pixel (dalla profondità, solo con i pixel dello stesso triangolo) e occlusione ambientale |
| 4 | `light.slang` | luce del gioco × occlusione + cielo notturno + luna + fiamme di RecompOne + luci degli effetti; ombre; metallo; acqua; nebbia. Il rapporto con la luce del gioco viene applicato all'immagine del gioco |
| 4b | `accum.slang` | accumulo temporale: riproietta nel fotogramma precedente e media con la storia limitata ai vicini; stabilizza acqua, riflessi, ombre e occlusione |
| 5 | `shafts.slang` | raggi della luna dal cielo visibile (mezza risoluzione) |
| 6-8 | `bloom_*.slang` | bagliore delle parti luminose |
| 9 | `final.slang` | bloom, raggi, esposizione, compressione delle sole parti molto luminose, saturazione, interfaccia sopra |

Il rapporto si applica all'immagine del gioco, non a una ricomposizione: scritte incise, decalcomanie e trasparenze sopra una superficie prendono la stessa luce della superficie. Dove il gioco ha portato il colore al nero (bordi della mappa, buchi) la luce del gioco è zero e il pixel resta nero. I pixel senza geometria opaca sotto (cielo, schermate 2D, interfaccia) restano identici al gioco.

## Parametri

- **View**: 0 risultato, 1 albedo, 2 luce del gioco, 3 normali, 4 triangoli, 5 profondità, 6 materiali, 7 occlusione, 8 rapporto di luce, 9 sola luce aggiunta, 10 superfici trattate come metallo (arancione), 11 acqua (blu), 12 livello dell'interfaccia di RecompOne.
- **Temporal smoothing**: quanto conta la storia dei fotogrammi precedenti (0 = niente accumulo).
- **Smooth surfaces**: normali smussate tra i poligoni della stessa superficie (0 = luce a poligoni piatti).
- **Sky fill light**: luce diffusa del cielo notturno, anche sulle superfici di spalle alla luna, con un po' di luce rimbalzata dal terreno e un bordo di controluce.
- **Game lighting**: quanto conta la luce originale del gioco.
- **Ambient occlusion**, **Occlusion radius**: ombre di contatto negli angoli e sotto gli oggetti.
- **Moonlight**, **Moon direction**, **Moon height**: luce della luna sulle superfici rivolte verso di lei.
- **Light sources**, **Light source range**, **Light source minimum reach**: luce delle fiamme, delle fonti di energia e delle magie (posizioni fornite da RecompOne); la portata minima evita che le luci degli sprite piccoli illuminino solo pochi pixel.
- **Light on overlays**: quanta luce nuova prendono menu semitrasparenti, effetti e scritte sopra le superfici (0 = come nel gioco).
- **Fog**, **Fog start**, **Fog end**, **Fog brightness**, **Base haze**: nebbia di distanza col colore del cielo del livello (tinto dalla maledizione) e foschia che si vede già da vicino; dove il gioco ha portato il colore al nero la nebbia non schiarisce.
- **Fog over sky**: foschia del colore del cielo su cielo e fondale (montagne, pareti dipinte), più fitta all'orizzonte.
- **Draw distance fade**: la geometria vicina al limite di disegno e il vuoto sotto l'orizzonte (oltre i bordi della mappa) vanno al nero, come nell'originale.
- **Shadows on game light**: quanto le ombre scuriscono anche la luce originale del gioco (che non ha ombre degli oggetti).
- **Indoor darkness**: al chiuso (poco cielo visibile in alto) luna, cielo e foschia a terra si attenuano.
- **Curse tint**, **Dark desaturation**: tinta verde-azzurra e colori smorzati nelle parti scure, come in Dan's Curse.
- **Bloom**, **Bloom threshold**: bagliore delle parti luminose.
- **Specular**: riflessi di luna e fiamme.
- **Shadows**, **Shadow length**: ombre della luna e della luce più forte in ogni punto, calcolate sull'immagine (gli oggetti fuori dallo schermo non fanno ombra).
- **Fire flicker**: tremolio delle luci color fuoco.
- **Metal reflections**: spade, scudi e armature riflettono la scena vicina (riflesso nello spazio schermo) o il cielo notturno, tinti dal colore del metallo, con riflessi forti di luna e fiamme. Il gioco non dice di che materiale è una superficie: il metallo si riconosce dal colore (argento chiaro e poco saturo, oro giallo e chiaro), solo su personaggi e oggetti (quello che il gioco non illumina con il colore dei vertici) e solo vicino alla telecamera, oltre che dal tag "metallo" di RecompOne.
- **Guess metal from colour**: stima del metallo dal colore sulle texture senza materiale (0 = solo le texture marcate come metallo).
- **Water reflections**, **Water waves**, **Water density**, **Water caustics**: acqua con onde animate, rifrazione del fondo, assorbimento con la profondità, caustiche e riflesso della scena (o del cielo) secondo l'angolo. Vale solo dove il gioco disegna davvero una superficie d'acqua; la sua altezza viene dal livello del lago del fork o dal piano dell'acqua di RecompOne.
- **Effect light**, **Effect light range**: quanto e fin dove illuminano le fonti di vita, le magie e gli altri effetti luminosi. Sono luci puntiformi 3D: illuminano anche le superfici rivolte dall'altra parte rispetto alla telecamera.
- **Moon glow in fog**: la nebbia si schiarisce guardando verso la luna.
- **Moon shafts**: raggi di luce dal cielo verso la telecamera, forti guardando verso la luna e deboli di lato.
- **Ground mist**, **Ground mist height**: foschia nelle zone più basse della telecamera, a chiazze che si muovono lentamente.
- **Maximum brightening**: quanto può schiarire al massimo una superficie rispetto al gioco.
- **Exposure**, **Saturation**, **Vignette**: resa finale.

Con *Game lighting* 1 e *Ambient occlusion*, *Moonlight*, *Light sources* e *Specular* a 0 l'immagine è identica al gioco.

## Crediti

Onde dell'acqua adattate da "Very fast procedural ocean" di afl_ext, vedi [THIRD_PARTY.txt](THIRD_PARTY.txt).

## License

GPL-3.0-or-later, vedi [LICENSE](LICENSE).

## Author

https://github.com/Leproide
