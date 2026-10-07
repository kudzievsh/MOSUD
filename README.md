# MOSUD Course

Репозиторий практических работ по дисциплине **«Математическое обеспечение систем управления данными»**.

Практические работы выполняются на PostgreSQL 17 с использованием открытого набора данных **Brazilian E-Commerce Public Dataset by Olist**. СУБД разворачивается в Docker, данные загружаются в базу `olist`.

## Структура репозитория

```text
MOSUD/
├── data/
│   └── olist/                 
├── lab01/
│   ├── docker-compose.yml
│   ├── schema.sql
│   ├── check.sql
│   └── README.md
├── lab02/
│   ├── lab02.sql
│   └── README.md
├── lab03/
│   ├── lab03.sql
│   └── README.md
├── lab04/
│   └── lab04.sql
├── lab05/
│   └── lab05.sql
├── lab06/
│   └── lab06.sql
├── lab07/
│   └── lab07.sql
├── .gitignore
└── README.md
```

## Практические работы

| Работа | Тема | Вариант | Файлы |
|---|---|---:|---|
| №1 | Развёртывание PostgreSQL и загрузка Olist | — | `lab01/docker-compose.yml`, `schema.sql`, `check.sql`, `README.md` |
| №2 | Множества и мультимножества в SQL | 3 | `lab02/lab02.sql`, `README.md` |
| №3 | Выборка, проекция, переименование и реляционная алгебра | 3 | `lab03/lab03.sql`, `README.md` |
| №4 | Соединения отношений и сложные JOIN | 3 | `lab04/lab04.sql` |
| №5 | Кванторы, EXISTS и реляционное деление | 3 | `lab05/lab05.sql` |
| №6 | Подзапросы и логика предикатов | 3 | `lab06/lab06.sql` |
| №7 | NULL, трёхзначная логика и качество данных | — | `lab07/lab07.sql` |
