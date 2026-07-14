update public.profiles
set role = 'owner'
where email = 'OWNER_EMAIL_HERE';

select id, email, role
from public.profiles
where role = 'owner';
