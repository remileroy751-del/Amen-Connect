# AMEN CONNECT — COLLEGE AMEN

Application mobile de gestion scolaire basée sur Kotlin / Jetpack Compose, avec interface Super Admin web et Supabase.

## Structure
- `app/` : application Android Parent / Enseignant.
- `admin/index.html` : interface Super Admin Direction.
- `index.html` : copie de l'interface web, utile pour GitHub Pages à la racine.
- `supabase/AMEN_CONNECT_SCHEMA.sql` : script SQL complet à exécuter dans Supabase.
- `.github/workflows/android.yml` : compilation automatique de l'APK Debug.

## Supabase
Projet : `https://cbiusjqmuknzsmffjntv.supabase.co`

La clé Publishable est intégrée dans l'application et dans l'interface web. Elle est conçue pour un usage client. Ne jamais mettre une clé `service_role` dans le dépôt.

## Installation de la base
Dans Supabase > SQL Editor, créer une nouvelle requête, copier tout le contenu de `supabase/AMEN_CONNECT_SCHEMA.sql`, puis cliquer sur **Run**.

Ensuite, dans Supabase > Authentication > Users, créer le compte e-mail + mot de passe de la Direction. Depuis l'interface Super Admin, utiliser l'initialisation du compte Direction avec ce compte.

## Message de la Direction
Les communiqués sont enregistrés dans `announcements`. Les RPC `student_announcements` et `acknowledge_announcement` assurent la lecture et l'accusé de réception côté parent. Le schéma inclut `student_id` dans `announcement_receipts` afin que l'accusé soit correctement lié à l'enfant sélectionné.

## Compilation GitHub
Le workflow installe Java 17, Gradle 8.9 et Android SDK 35, puis exécute `gradle assembleDebug`.

## Mot de passe supplémentaire pour créer une classe
Pour conserver l'architecture existante, la création d'une classe depuis l'admin demande un mot de passe Direction distinct du mot de passe Supabase. Dans le script SQL fourni, sa valeur initiale est : `AMEN-Classe-2026!`. Vous pouvez la remplacer avant l'exécution du script si vous le souhaitez.

### Sécurité de l'initialisation Direction
Le premier compte Auth qui exécute l'initialisation devient administrateur. Une fois un administrateur présent, un autre compte Auth ne peut pas s'auto-ajouter comme administrateur via cette fonction.
