# YadrenoVPN-Docker

Шпаргалка по сборке и развёртыванию контейнерного образа YadrenoVPN (бот) с помощью Docker и Docker Compose.

Документ покрывает:
- сборку образа локально;
- подготовку docker-compose.yml с именованными томами и init-perms;
- пример .env.example (без секретов);
- перенос образа в регистр / экспорт-импорт;
- развёртывание стека (локально или на платформе типа Dockhand);
- быстрое восстановление и отзыва токена.

Важно: не храните в репозитории реальные секреты (BOT_TOKEN и т.д.). Используйте `.env` локально или секреты платформы.

---

## Быстрый старт — собрать образ локально

В корне репозитория (где расположен `Dockerfile`) выполните одну из команд:

Обычная сборка Docker:

```bash
docker build --no-cache \
  --build-arg REPO_URL=https://github.com/plushkinv/YadrenoVPN.git \
  --build-arg REPO_REF=main \
  -t yadrenvpn-docker:latest .
```

Рекомендуемый вариант — с BuildKit / buildx (поддерживает --load):

```bash
docker buildx create --use --name mybuilder || true
docker buildx build --no-cache \
  --build-arg REPO_URL=https://github.com/plushkinv/YadrenoVPN.git \
  --build-arg REPO_REF=main \
  -t yadrenvpn-docker:latest --load .
```

Проверить собранный образ:

```bash
docker images | grep yadrenvpn-docker
```

---

## Пример .env.example (НЕ КОММИТИТЕ реальные токены)

```text
# копируйте в .env и заполните реальные значения
BOT_TOKEN=REPLACE_ME
ADMIN_IDS=123456789
REPO_URL=https://github.com/plushkinv/YadrenoVPN.git
REPO_REF=main
```

Сохраните реальный `.env` локально на сервере или задавайте secret в платформе (Dockhand, Heroku, Docker Swarm/K8s secrets).

---

## docker-compose.yml — рекомендованный пример

Сохраняйте этот файл рядом с `.env` на сервере/в стеке. Он использует именованные тома и включает вспомогательный сервис `init-perms` для корректных прав.

```yaml
version: "3.8"
services:
  yadreno:
    image: yadrenvpn-docker:latest # или registry.example.com/namespace/yadrenvpn-docker:latest
    restart: unless-stopped
    env_file:
      - .env
    environment:
      - BOT_TOKEN=${BOT_TOKEN}
      - ADMIN_IDS=${ADMIN_IDS}
    volumes:
      - yadreno_db:/app/database
      - yadreno_logs:/app/logs
    networks:
      - yadreno_net

  init-perms:
    image: alpine:latest
    command: ["sh", "-c", "mkdir -p /app/logs /app/database && chown -R 1000:1000 /app/logs /app/database && chmod -R u+rwX /app/logs /app/database"]
    volumes:
      - yadreno_db:/app/database
      - yadreno_logs:/app/logs
    restart: "no"

volumes:
  yadreno_db:
  yadreno_logs:

networks:
  yadreno_net:
    driver: bridge
```

Как пользоваться:
1. Заполните `.env` рядом с `docker-compose.yml` (не в репо).
2. Однократно выполните:

```bash
# создаст тома и выставит права
docker-compose run --rm init-perms
```

3. Затем пересоберите и запустите сервис:

```bash
docker-compose build --no-cache
docker-compose up -d
```

Если используете `docker compose` (CLI v2): замените `docker-compose` на `docker compose`.

---

## Запуск контейнера вручную (без compose)

Если хотите быстро протестировать образ:

```bash
docker volume create yadreno_db
docker volume create yadreno_logs
# создать локальный .env с секретами
docker run -d --name yadreno_test \
  -v yadreno_db:/app/database -v yadreno_logs:/app/logs \
  --env-file .env yadrenvpn-docker:latest
```

Проверить логи:

```bash
docker logs -f yadreno_test
```

---

## Доставка образа на сервер / регистр

Вариант A — Push в Docker Hub / GHCR / приватный регистр

```bash
# Docker Hub
docker tag yadrenvpn-docker:latest youruser/yadrenvpn-docker:latest
docker push youruser/yadrenvpn-docker:latest

# GHCR (пример)
docker tag yadrenvpn-docker:latest ghcr.io/yourorg/yadrenvpn-docker:latest
echo $GHCR_TOKEN | docker login ghcr.io -u YOUR_GH_USERNAME --password-stdin
docker push ghcr.io/yourorg/yadrenvpn-docker:latest
```

Вариант B — экспорт/импорт (если нет регистра)

```bash
docker save yadrenvpn-docker:latest -o yadrenvpn-docker.tar
# скопировать на сервер: scp yadrenvpn-docker.tar user@server:/tmp/
# на сервере:
docker load -i /tmp/yadrenvpn-docker.tar
```

---

## Развёртывание в Dockhand (или другой PaaS)

- Загрузите/укажите образ (registry или загруженный локально).
- Создайте защищённый `.env` через UI (или используйте Secrets) и не храните токены в репо.
- Добавьте `docker-compose.yml` в стек/проект и запустите init-perms (one-off) перед основным запуском.

---

## Восстановление / отзыв токена

Если токен попал в логи/чат/репо — отзовите и сгенерируйте новый в BotFather:

1. В BotFather → Manage Bot → API Token → Revoke current token / Generate new token.
2. Обновите `.env` на сервере (не в репо).
3. Перезапустите контейнеры:

```bash
docker-compose down && docker-compose up -d --build
```

---

## Отладка прав и томов

Если при запуске возникнут ошибки прав доступа (PermissionError) к `/app/logs` или `/app/database`:

```bash
# проверить права в томе
docker run --rm -v yadreno_logs:/data alpine ls -la /data
# выставить права вручную
docker run --rm -v yadreno_db:/app/database -v yadreno_logs:/app/logs alpine sh -c "chown -R 1000:1000 /app/logs /app/database && chmod -R u+rwX /app/logs /app/database"
```

Или используйте `init-perms` из `docker-compose.yml` (рекомендуется).

---

## Полезные команды

```bash
# посмотреть образы
docker images | grep yadrenvpn

# удалить локальный образ
docker rmi yadrenvpn-docker:latest

# просмотреть логи
docker-compose logs -f yadreno

# полностью сбросить стек и тома
docker-compose down --remove-orphans --volumes
```

---

## Безопасность и рекомендации

- Никогда не коммитьте `.env` с реальными ключами. В репо держите `.env.example`.
- Регулярно регенерируйте токены при подозрениях на утечку.
- Используйте менеджер секретов платформы для продакшен-развёртываний.

---

Если хотите, я могу сразу:
- добавить этот README.md в репозиторий (в main) — сделаю коммит и push, или
- вывести финальный блок здесь, чтобы вы вставили сами.

Скажите, выполнить коммит в `kit-66/YadrenoVPN-Docker` (main)?