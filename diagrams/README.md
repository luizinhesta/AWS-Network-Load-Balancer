# Diagramas de Arquitetura

Este diretório contém os diagramas de arquitetura do projeto AWS Luanti ALB/NLB em formato Mermaid (`.mmd`) e suas respectivas imagens exportadas (`.png`).

## Arquivos neste diretório

| Arquivo | Descrição |
|---------|-----------|
| `arquitetura.mmd` | Diagrama Mermaid da arquitetura geral do projeto (Internet → Route53 → ALB/NLB → Target Groups → ASGs → EC2) |
| `arquitetura.png` | Imagem exportada do diagrama de arquitetura *(a ser gerado pelo usuário)* |
| `README.md` | Este arquivo com instruções de uso |

## Como gerar arquitetura.png

A imagem `arquitetura.png` é um **placeholder** que deve ser gerado pelo usuário a partir do arquivo `arquitetura.mmd`. Abaixo estão as opções disponíveis para exportação.

### Opção 1: Mermaid CLI (recomendado)

Utilize o pacote `@mermaid-js/mermaid-cli` para gerar a imagem via linha de comando:

```bash
npx @mermaid-js/mermaid-cli@latest -i arquitetura.mmd -o arquitetura.png
```

Para personalizar a resolução e o tema:

```bash
npx @mermaid-js/mermaid-cli@latest -i arquitetura.mmd -o arquitetura.png --width 1920 --backgroundColor white
```

**Pré-requisitos:** Node.js instalado (versão 16 ou superior).

### Opção 2: Mermaid Live Editor (online)

1. Acesse o editor online: [https://mermaid.live](https://mermaid.live)
2. Cole o conteúdo do arquivo `arquitetura.mmd` no painel de edição
3. Visualize o diagrama renderizado no painel direito
4. Clique no botão de download (ícone de imagem) e selecione **PNG**
5. Salve o arquivo como `arquitetura.png` neste diretório

### Opção 3: Extensão VS Code

1. Instale a extensão **Mermaid Markdown Syntax Highlighting** no VS Code
2. Abra o arquivo `arquitetura.mmd`
3. Utilize o comando `Mermaid: Export` para gerar a imagem PNG
4. Salve o arquivo exportado como `arquitetura.png` neste diretório

## Observações

- O arquivo `arquitetura.png` **não é versionado automaticamente** — ele deve ser gerado localmente pelo usuário após clonar o repositório.
- Caso o diagrama `.mmd` seja atualizado, regenere a imagem PNG para manter a documentação consistente.
- A imagem gerada é referenciada pelo portal web (`web/index.html`) e pela documentação de arquitetura (`ARQUITETURA.md`).
