# AMEN CONNECT — Super Admin Web

Interface web de gestion du **COLLEGE AMEN**.

## Connexion
1. Créez le compte Direction dans Supabase > Authentication > Users avec l'e-mail et le mot de passe choisis par l'établissement.
2. Ouvrez l'interface Super Admin.
3. Connectez-vous avec ce compte.
4. Utilisez « RÉACTIVER / INITIALISER » pour inscrire ce compte dans `admin_users`.

La clé Publishable Supabase peut être utilisée côté navigateur. Ne jamais placer une clé `service_role` dans le dépôt.

## Message de la Direction
Les publications « À tous les parents » et « Aux parents d'une classe » sont enregistrées dans `announcements`. L'application Parent appelle `student_announcements` pour récupérer les messages correspondant réellement à l'enfant sélectionné. Les nouveaux messages sont suivis par enfant dans `announcement_reads` : le compteur « nouveau(x) message(s) » revient à zéro lorsque le parent ouvre « Message de la Direction ». Il n'y a plus d'accusé de réception « Bien reçu ».
