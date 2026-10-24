# Identidade visual — Economizze

![Logo no fundo claro](png/logo-claro.png)

## Conceito

**A moeda "zz".** O "zz" é o que torna o nome *Economizze* único, então ele virou o símbolo:
dois "z" ligados dentro de uma moeda, com o segundo um degrau acima do primeiro — o dinheiro
que sobra e sobe. O mesmo "zz" aparece em destaque no nome escrito, amarrando símbolo e palavra.

O mascote (o Cofrinho) continua: agora ele recebe a moeda da marca.

## Símbolo e logo

| Arquivo | Uso |
|---|---|
| `svg/simbolo.svg` | Moeda lima com "zz" tinta. Uso padrão do símbolo. |
| `svg/simbolo-contorno.svg` | Versão em traço, para tamanhos grandes e fundos claros onde a moeda cheia pesa demais. |
| `svg/simbolo-silhueta.svg` | Silhueta de uma cor com o "zz" vazado: notificação, ícone monocromático, carimbos. |
| `svg/icone-app.svg` | Ícone do app: moeda lima sobre fundo tinta. |
| `svg/logo-claro.svg` | Símbolo + nome para fundos claros (moeda e "zz" em mar, texto em tinta). |
| `svg/logo-escuro.svg` | Símbolo + nome para fundos escuros (moeda e "zz" em lima, texto branco). |
| `svg/mascote.svg` | O Cofrinho com a moeda. |

O nome é escrito em **minúsculas** — `economizze` — em Nunito Black, com o `zz` na cor de destaque.
No app, o componente `Wordmark` (`mobile/lib/widgets/playful.dart`) faz isso.

**Área de respiro:** deixe em volta do logo pelo menos a altura do "z".
**Tamanho mínimo:** símbolo com 16 px; logo horizontal com 96 px de largura.

### Ícones de status (ícone que muda com o mês)

| Arquivo | Quando |
|---|---|
| `svg/icone-app.svg` | Padrão: mês no azul ou sem dados. O zz sobe. |
| `svg/icone-app-atencao.svg` | Atenção: sobrou pouco. Moeda âmbar `#FFB547`, os dois z no mesmo nível. |
| `svg/icone-app-alerta.svg` | No vermelho: gastou mais do que entrou. Moeda coral `#FF7A6B`, o zz desce. |

Única exceção à regra do degrau: aqui a altura dos z conta a situação. Âmbar e coral só aparecem nesses ícones.

## Cores

| Nome | Hex | Papel |
|---|---|---|
| Tinta | `#0B2B2E` | Texto forte, fundo do ícone, fundo do tema escuro |
| Mar | `#0C7A68` | Cor principal no tema claro: botões, links, seleção |
| Lima | `#C5F04A` | Destaque: moeda, "zz", ação principal ("Lançar"), cor principal no tema escuro |
| Névoa | `#F2F6F4` | Fundo do tema claro |
| Receita | `#13864D` | Valores que entram |
| Despesa | `#D24148` | Valores que saem |
| Alerta | `#A96404` | Avisos (orçamento perto do limite) |

Contrastes (WCAG): branco sobre mar **5,25:1**; tinta sobre lima **11,4:1**; lima sobre o fundo
escuro **13,1:1**; tinta sobre névoa **13,8:1**. Receita, despesa e alerta passam de **4,5:1** sobre
o branco e de **3:1** sobre o cartão escuro, para servirem aos dois temas com uma cor só.

**Não use lima como texto ou ícone sobre fundo claro** (1,3:1, ilegível). No claro, a lima só
aparece como fundo de algo com texto tinta (o botão "Lançar", o indicador da barra inferior).

Degradê de destaque (cartão do saldo, login, apresentação): **mar → tinta**, na diagonal.

## Tipografia

**Nunito** em todo o app (já incluída em `mobile/assets/fonts`, licença OFL). Títulos e nome da marca
em Black (900) ou ExtraBold (800); textos em SemiBold (600) e Medium (500).

## Não faça

- Mudar as cores do símbolo fora das combinações acima (ex.: moeda mar com "zz" lima).
- Separar os dois "z" ou alinhar os dois na mesma altura: o degrau é a ideia.
- Escrever "Economizze" com Z maiúsculo ou outra fonte no logo.
- Pôr o logo sobre fotos ou fundos sem contraste.

## Como regenerar

Todos os SVGs, as prévias e os ícones do app (Android, iOS, web, notificação e o mascote em
`mobile/assets/mascot.png`) saem de `gerar.py`:

```bash
pip install -r brand/requirements.txt
python brand/gerar.py
```

A geometria do símbolo e a paleta ficam no topo do script. As cores do app ficam em
`mobile/lib/theme.dart` (tinta, mar, lima, névoa) e `mobile/lib/utils/format.dart` (receita, despesa, alerta).
